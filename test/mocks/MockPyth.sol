// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockPyth - Mock Pyth oracle for testing
contract MockPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    mapping(bytes32 => Price) public prices;

    function setPrice(bytes32 id, int64 price, uint64 conf, int32 expo) external {
        prices[id] = Price({price: price, conf: conf, expo: expo, publishTime: block.timestamp});
    }

    function getUpdateFee(bytes[] calldata) external pure returns (uint256) {
        return 0;
    }

    function updatePriceFeeds(bytes[] calldata) external payable {}

    function getPriceNoOlderThan(bytes32 id, uint256) external view returns (Price memory) {
        return prices[id];
    }
}
