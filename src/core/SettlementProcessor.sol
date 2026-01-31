// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISettlementProcessor} from "../interfaces/ISettlementProcessor.sol";
import {IEventManager} from "../interfaces/IEventManager.sol";
import {IBettingEngine} from "../interfaces/IBettingEngine.sol";
import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";
import {MicroEventLib} from "../libraries/MicroEventLib.sol";

/// @title SettlementProcessor - Batch settlement for micro-events
/// @notice Settles up to 50 events per tx using Pyth oracle data.
///         Settlement runs AFTER betting windows close (not on hot path).
contract SettlementProcessor is ISettlementProcessor {
    // ===================== STORAGE =====================

    IEventManager public immutable eventManager;
    IBettingEngine public immutable bettingEngine;
    IOracleAdapter public immutable oracleAdapter;

    mapping(address => bool) public authorizedSettlers;
    address public owner;

    // ===================== CONSTRUCTOR =====================

    constructor(address _eventManager, address _bettingEngine, address _oracleAdapter) {
        eventManager = IEventManager(_eventManager);
        bettingEngine = IBettingEngine(_bettingEngine);
        oracleAdapter = IOracleAdapter(_oracleAdapter);
        owner = msg.sender;
    }

    // ===================== SETTLEMENT =====================

    /// @notice Settle a batch of locked events
    function settleBatch(
        bytes32[] calldata eventIds,
        bytes[] calldata priceUpdateData,
        uint8[] calldata winningOutcomes
    ) external payable {
        require(authorizedSettlers[msg.sender], "Settlement: not authorized");
        require(eventIds.length == winningOutcomes.length, "Settlement: length mismatch");
        require(eventIds.length <= 50, "Settlement: batch too large");

        // Update oracle prices once for the batch (amortize Pyth fee)
        if (priceUpdateData.length > 0) {
            oracleAdapter.updateAndGetPrice{value: msg.value}(bytes32(0), priceUpdateData);
        }

        for (uint256 i = 0; i < eventIds.length;) {
            bytes32 eventId = eventIds[i];
            uint8 winOutcome = winningOutcomes[i];

            try this.settleOne(eventId, winOutcome) {}
            catch (bytes memory reason) {
                emit EventSettlementFailed(eventId, reason);
            }

            unchecked {
                ++i;
            }
        }

        emit BatchSettled(eventIds, block.timestamp);
    }

    /// @notice Settle a single event (external for try/catch)
    function settleOne(bytes32 eventId, uint8 winningOutcome) external {
        require(msg.sender == address(this), "Settlement: internal only");

        (,,, MicroEventLib.EventStatus status, uint8 numOutcomes,,,,) = eventManager.getEvent(eventId);
        require(status == MicroEventLib.EventStatus.LOCKED, "Settlement: not locked");

        // Aggregate shards -> write outcome totals in BettingEngine
        bettingEngine.aggregateForSettlement(eventId, numOutcomes);

        // Mark event as settled with winning outcome
        eventManager.settleEvent(eventId, winningOutcome);
    }

    /// @notice Void a batch of events
    function voidBatch(bytes32[] calldata eventIds) external {
        require(authorizedSettlers[msg.sender], "Settlement: not authorized");

        for (uint256 i = 0; i < eventIds.length;) {
            eventManager.voidEvent(eventIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    function isSettleable(bytes32 eventId) external view returns (bool) {
        (,,, MicroEventLib.EventStatus status,,,,, ) = eventManager.getEvent(eventId);
        return status == MicroEventLib.EventStatus.LOCKED;
    }

    // ===================== ADMIN =====================

    function setSettler(address settler, bool authorized) external {
        require(msg.sender == owner, "Settlement: not owner");
        authorizedSettlers[settler] = authorized;
    }
}
