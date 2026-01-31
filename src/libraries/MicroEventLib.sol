// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MicroEventLib - Micro-event lifecycle utilities
/// @notice Handles event ID generation, window validation, and status checks
///         for 5-30 second betting windows.
library MicroEventLib {
    uint40 internal constant MIN_WINDOW = 30;
    uint40 internal constant MAX_WINDOW = 60;

    enum EventStatus {
        NONEXISTENT,
        OPEN,
        LOCKED,
        SETTLED,
        VOIDED
    }

    error InvalidWindow(uint40 duration);
    error EventNotOpen(bytes32 eventId);
    error EventNotLocked(bytes32 eventId);
    error EventAlreadyExists(bytes32 eventId);
    error BettingWindowClosed(bytes32 eventId);

    /// @notice Generate deterministic event ID from parameters
    function generateEventId(
        bytes32 priceFeedId,
        uint40 openTime,
        uint40 closeTime,
        uint256 nonce
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(priceFeedId, openTime, closeTime, nonce));
    }

    /// @notice Validate betting window duration is within 5-30 seconds
    function validateWindow(uint40 openTime, uint40 closeTime) internal pure {
        uint40 duration = closeTime - openTime;
        if (duration < MIN_WINDOW || duration > MAX_WINDOW) {
            revert InvalidWindow(duration);
        }
    }

    /// @notice Check if event is currently accepting bets
    function isAcceptingBets(
        uint40 openTime,
        uint40 closeTime,
        EventStatus status
    ) internal view returns (bool) {
        return status == EventStatus.OPEN
            && block.timestamp >= openTime
            && block.timestamp < closeTime;
    }
}
