// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MicroEventLib} from "../libraries/MicroEventLib.sol";

interface IEventManager {
    event EventCreated(bytes32 indexed eventId, uint40 openTime, uint40 closeTime, bytes32 priceFeedId);
    event EventLocked(bytes32 indexed eventId);
    event EventSettled(bytes32 indexed eventId, uint8 winningOutcome);
    event EventVoided(bytes32 indexed eventId);

    /// @notice Create a new micro-event (keeper only)
    function createEvent(
        bytes32 priceFeedId,
        uint40 openTime,
        uint40 closeTime,
        uint8 numOutcomes,
        bytes32 auraAttestation
    ) external returns (bytes32 eventId);

    /// @notice Lock event when betting window closes
    function lockEvent(bytes32 eventId) external;

    /// @notice Settle event with winning outcome (settlement processor only)
    function settleEvent(bytes32 eventId, uint8 winningOutcome) external;

    /// @notice Void event (settlement processor only)
    function voidEvent(bytes32 eventId) external;

    /// @notice Get full event details
    function getEvent(bytes32 eventId) external view returns (
        uint40 openTime,
        uint40 closeTime,
        uint40 settleTime,
        MicroEventLib.EventStatus status,
        uint8 numOutcomes,
        address creator,
        bytes32 priceFeedId,
        uint8 winningOutcome,
        bytes32 auraAttestation
    );

    /// @notice Check if event is accepting bets
    function isAcceptingBets(bytes32 eventId) external view returns (bool);
}
