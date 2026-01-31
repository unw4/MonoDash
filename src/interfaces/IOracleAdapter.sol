// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IOracleAdapter {
    /// @notice Update price feeds and return the latest price
    function updateAndGetPrice(
        bytes32 priceFeedId,
        bytes[] calldata priceUpdateData
    ) external payable returns (int64 price, uint64 conf, int32 expo, uint256 publishTime);

    /// @notice Get cached price without updating
    function getCachedPrice(
        bytes32 priceFeedId,
        uint256 maxStaleness
    ) external view returns (int64 price, uint64 conf, int32 expo, uint256 publishTime);
}
