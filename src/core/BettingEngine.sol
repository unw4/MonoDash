// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IBettingEngine} from "../interfaces/IBettingEngine.sol";
import {IEventManager} from "../interfaces/IEventManager.sol";
import {IUserVault} from "../interfaces/IUserVault.sol";
import {ShardLib} from "../libraries/ShardLib.sol";
import {BetLib} from "../libraries/BetLib.sol";
import {MicroEventLib} from "../libraries/MicroEventLib.sol";

/// @title BettingEngine - Sharded-state betting for Monad parallel execution
/// @notice PARALLELISM DESIGN:
///   1. userBets[user][eventId] -> per-user slot = PARALLEL SAFE across users
///   2. poolShards[eventId][outcome][shard] -> per-shard slot = 93.75% parallel (16 shards)
///   3. UserVault.lockBalance(user) -> per-user slot = PARALLEL SAFE
///   Net: two users betting simultaneously almost always execute fully in parallel.
contract BettingEngine is IBettingEngine {
    // ===================== STORAGE =====================

    /// @notice Per-user, per-event bet record
    /// Storage: keccak256(eventId . keccak256(user . SLOT)) -> unique per (user, event)
    mapping(address => mapping(bytes32 => BetLib.UserBet)) private _userBets;

    /// @notice Sharded pool: poolShards[eventId][outcomeIndex][shardIndex]
    /// 16 independent shards per outcome -> parallel safe across shards
    mapping(bytes32 => mapping(uint8 => mapping(uint8 => ShardLib.PoolShard))) private _poolShards;

    /// @notice Aggregated outcome totals (written ONLY during settlement)
    mapping(bytes32 => mapping(uint8 => uint128)) private _outcomeTotals;

    /// @notice Total pool per event (written ONLY during settlement)
    mapping(bytes32 => uint128) private _eventTotals;

    /// @notice Accumulated house fees per event
    mapping(bytes32 => uint128) private _houseFees;

    // ===================== DEPENDENCIES =====================

    IEventManager public immutable eventManager;
    IUserVault public immutable userVault;
    address public sessionKeyManager;
    address public settlementProcessor;
    address public owner;

    // ===================== CONSTRUCTOR =====================

    constructor(address _eventManager, address _userVault) {
        eventManager = IEventManager(_eventManager);
        userVault = IUserVault(_userVault);
        owner = msg.sender;
    }

    // ===================== BET PLACEMENT (HOT PATH) =====================

    /// @notice Place a bet directly (user signs tx)
    function placeBet(bytes32 eventId, uint8 outcomeIndex, uint128 amount) external {
        _placeBetInternal(msg.sender, eventId, outcomeIndex, amount);
    }

    /// @notice Place a bet via session key (delegated signer)
    function placeBetDelegated(
        address user,
        bytes32 eventId,
        uint8 outcomeIndex,
        uint128 amount
    ) external {
        require(msg.sender == sessionKeyManager, "BettingEngine: not session manager");
        _placeBetInternal(user, eventId, outcomeIndex, amount);
    }

    /// @dev Internal bet placement — the critical hot path
    /// STORAGE WRITES (all parallel-safe across users):
    ///   1. _userBets[user][eventId]                        -> per-user slot
    ///   2. _poolShards[eventId][outcome][shard]             -> per-shard slot
    ///   3. UserVault._balances[user] (via lockBalance)      -> per-user slot
    ///   4. UserVault._lockedBalances[user] (via lockBalance) -> per-user slot
    function _placeBetInternal(
        address user,
        bytes32 eventId,
        uint8 outcomeIndex,
        uint128 amount
    ) internal {
        // 1. Validate event is accepting bets (read-only)
        require(eventManager.isAcceptingBets(eventId), "BettingEngine: not accepting bets");

        // 2. Get event details for outcome count validation (read-only)
        (,,, MicroEventLib.EventStatus status, uint8 numOutcomes,,,,) = eventManager.getEvent(eventId);

        // 3. Validate bet parameters (pure)
        BetLib.validateBet(amount, outcomeIndex, numOutcomes);

        // 4. Check user hasn't already bet on this event (per-user SLOAD)
        require(_userBets[user][eventId].amount == 0, "BettingEngine: already bet");

        // 5. Lock user's balance in vault (per-user SSTORE)
        userVault.lockBalance(user, amount);

        // 6. Record user's bet (per-user SSTORE)
        _userBets[user][eventId] = BetLib.UserBet({
            amount: amount,
            outcomeIndex: outcomeIndex,
            timestamp: uint40(block.timestamp),
            settled: false
        });

        // 7. Update sharded pool (per-shard SSTORE)
        uint8 shard = ShardLib.shardIndex(user);
        ShardLib.PoolShard storage poolShard = _poolShards[eventId][outcomeIndex][shard];
        poolShard.totalStaked += amount;
        poolShard.betCount += 1;

        emit BetPlaced(user, eventId, outcomeIndex, amount, shard);
    }

    // ===================== CLAIM PAYOUT =====================

    /// @notice Claim payout for a settled event
    function claimPayout(bytes32 eventId) external {
        BetLib.UserBet storage bet = _userBets[msg.sender][eventId];
        require(bet.amount > 0, "BettingEngine: no bet");
        require(!bet.settled, "BettingEngine: already settled");

        (,,, MicroEventLib.EventStatus status,,,, uint8 winningOutcome,) = eventManager.getEvent(eventId);

        if (status == MicroEventLib.EventStatus.SETTLED) {
            bet.settled = true;

            if (bet.outcomeIndex == winningOutcome) {
                // Winner: proportional payout from total pool
                uint128 winTotal = _outcomeTotals[eventId][winningOutcome];
                uint128 eventTotal = _eventTotals[eventId];

                (uint128 payout, uint128 fee) = BetLib.calculatePayout(bet.amount, winTotal, eventTotal);

                userVault.deductLocked(msg.sender, bet.amount);
                userVault.creditWinnings(msg.sender, payout);
                _houseFees[eventId] += fee;

                emit BetSettled(msg.sender, eventId, payout);
            } else {
                // Loser: deduct locked balance
                userVault.deductLocked(msg.sender, bet.amount);
                emit BetSettled(msg.sender, eventId, 0);
            }
        } else if (status == MicroEventLib.EventStatus.VOIDED) {
            // Voided: refund locked balance
            bet.settled = true;
            userVault.unlockBalance(msg.sender, bet.amount);
            emit BetSettled(msg.sender, eventId, bet.amount);
        } else {
            revert("BettingEngine: event not settled or voided");
        }
    }

    // ===================== SETTLEMENT SUPPORT =====================

    /// @notice Aggregate all shards for an event and store outcome totals
    /// @dev Called once per event during batch settlement. Not on betting hot path.
    function aggregateForSettlement(bytes32 eventId, uint8 numOutcomes) external {
        require(msg.sender == settlementProcessor, "BettingEngine: not settlement");

        uint128 eventTotal = 0;
        for (uint8 outcome = 0; outcome < numOutcomes;) {
            (uint128 outcomeStaked,) = ShardLib.aggregateShards(_poolShards[eventId][outcome]);
            _outcomeTotals[eventId][outcome] = outcomeStaked;
            eventTotal += outcomeStaked;
            unchecked {
                ++outcome;
            }
        }
        _eventTotals[eventId] = eventTotal;
    }

    // ===================== VIEW FUNCTIONS =====================

    function getUserBet(address user, bytes32 eventId) external view returns (BetLib.UserBet memory) {
        return _userBets[user][eventId];
    }

    function getOutcomeTotal(bytes32 eventId, uint8 outcomeIndex) external view returns (uint128) {
        (uint128 total,) = ShardLib.aggregateShards(_poolShards[eventId][outcomeIndex]);
        return total;
    }

    function getHouseFees(bytes32 eventId) external view returns (uint128) {
        return _houseFees[eventId];
    }

    // ===================== ADMIN =====================

    function setSessionKeyManager(address _skm) external {
        require(msg.sender == owner, "BettingEngine: not owner");
        sessionKeyManager = _skm;
    }

    function setSettlementProcessor(address _sp) external {
        require(msg.sender == owner, "BettingEngine: not owner");
        settlementProcessor = _sp;
    }
}
