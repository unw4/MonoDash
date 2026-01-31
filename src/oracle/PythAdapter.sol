// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";

/// @dev Minimal Pyth interface to avoid npm dependency
interface IPythMinimal {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    function getUpdateFee(bytes[] calldata updateData) external view returns (uint256 feeAmount);
    function updatePriceFeeds(bytes[] calldata updateData) external payable;
    function getPriceNoOlderThan(bytes32 id, uint256 age) external view returns (Price memory price);
}

/// @title PythAdapter - Pyth Network oracle integration for MonoDash
/// @notice Wraps Pyth's pull-based oracle for low-latency price feeds.
/// @dev Pyth updates every 400ms on Pythnet, matching Monad's 400ms block time.
contract PythAdapter is IOracleAdapter {
    // ===================== STORAGE =====================

    IPythMinimal public immutable pyth;
    address public owner;
    uint256 public maxStaleness = 60;
    mapping(bytes32 => bool) public registeredFeeds;

    // ===================== CONSTRUCTOR =====================

    constructor(address _pythContract) {
        pyth = IPythMinimal(_pythContract);
        owner = msg.sender;
    }

    // ===================== ORACLE FUNCTIONS =====================

    /// @notice Update prices and return the latest for a specific feed
    function updateAndGetPrice(
        bytes32 priceFeedId,
        bytes[] calldata priceUpdateData
    ) external payable returns (int64 price, uint64 conf, int32 expo, uint256 publishTime) {
        if (priceUpdateData.length > 0) {
            uint256 fee = pyth.getUpdateFee(priceUpdateData);
            require(msg.value >= fee, "PythAdapter: insufficient fee");

            pyth.updatePriceFeeds{value: fee}(priceUpdateData);

            // Refund excess
            if (msg.value > fee) {
                (bool ok,) = msg.sender.call{value: msg.value - fee}("");
                require(ok, "PythAdapter: refund failed");
            }
        }

        if (priceFeedId != bytes32(0)) {
            IPythMinimal.Price memory p = pyth.getPriceNoOlderThan(priceFeedId, maxStaleness);
            return (p.price, p.conf, p.expo, p.publishTime);
        }
    }

    /// @notice Get cached price without updating
    function getCachedPrice(
        bytes32 priceFeedId,
        uint256 _maxStaleness
    ) external view returns (int64 price, uint64 conf, int32 expo, uint256 publishTime) {
        IPythMinimal.Price memory p = pyth.getPriceNoOlderThan(priceFeedId, _maxStaleness);
        return (p.price, p.conf, p.expo, p.publishTime);
    }

    // ===================== ADMIN =====================

    function registerFeed(bytes32 feedId) external {
        require(msg.sender == owner, "PythAdapter: not owner");
        registeredFeeds[feedId] = true;
    }

    function setMaxStaleness(uint256 _maxStaleness) external {
        require(msg.sender == owner, "PythAdapter: not owner");
        maxStaleness = _maxStaleness;
    }
}
