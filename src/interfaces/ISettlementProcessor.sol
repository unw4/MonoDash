// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISettlementProcessor {
    event BatchSettled(bytes32[] eventIds, uint256 timestamp);
    event EventSettlementFailed(bytes32 indexed eventId, bytes reason);

    /// @notice Settle a batch of events with oracle data
    function settleBatch(
        bytes32[] calldata eventIds,
        bytes[] calldata priceUpdateData,
        uint8[] calldata winningOutcomes
    ) external payable;

    /// @notice Void a batch of events
    function voidBatch(bytes32[] calldata eventIds) external;

    /// @notice Check if an event is ready for settlement
    function isSettleable(bytes32 eventId) external view returns (bool);
}
