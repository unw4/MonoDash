// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BetLib} from "../libraries/BetLib.sol";

interface IBettingEngine {
    event BetPlaced(
        address indexed user,
        bytes32 indexed eventId,
        uint8 outcomeIndex,
        uint128 amount,
        uint8 shardIndex
    );
    event BetSettled(address indexed user, bytes32 indexed eventId, uint128 payout);

    /// @notice Place a bet on a micro-event outcome
    function placeBet(bytes32 eventId, uint8 outcomeIndex, uint128 amount) external;

    /// @notice Place a bet via session key (delegated signer)
    function placeBetDelegated(
        address user,
        bytes32 eventId,
        uint8 outcomeIndex,
        uint128 amount
    ) external;

    /// @notice Claim payout for a settled event
    function claimPayout(bytes32 eventId) external;

    /// @notice Aggregate shard data for settlement
    function aggregateForSettlement(bytes32 eventId, uint8 numOutcomes) external;

    /// @notice Read a user's bet for an event
    function getUserBet(address user, bytes32 eventId) external view returns (BetLib.UserBet memory);

    /// @notice Get total staked on an outcome (aggregated across all shards)
    function getOutcomeTotal(bytes32 eventId, uint8 outcomeIndex) external view returns (uint128);
}
