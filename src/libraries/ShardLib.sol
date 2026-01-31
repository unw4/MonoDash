// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ShardLib - Storage slot sharding for Monad parallel execution
/// @notice Distributes pool writes across 16 shards so concurrent bettors
///         hit different storage slots 93.75% of the time.
/// @dev Shard index derived from last 4 bits of user address (bitwise AND).
library ShardLib {
    uint8 internal constant NUM_SHARDS = 16;
    uint8 internal constant SHARD_MASK = 0x0F;

    struct PoolShard {
        uint128 totalStaked;
        uint64 betCount;
    }

    /// @notice Deterministic shard assignment from address
    function shardIndex(address user) internal pure returns (uint8) {
        return uint8(uint160(user) & SHARD_MASK);
    }

    /// @notice Aggregate total staked across all shards for one outcome
    /// @dev Read-only aggregation, called during settlement (not on hot path)
    function aggregateShards(
        mapping(uint8 => PoolShard) storage shards
    ) internal view returns (uint128 totalStaked, uint64 totalBets) {
        for (uint8 i = 0; i < NUM_SHARDS;) {
            PoolShard storage s = shards[i];
            totalStaked += s.totalStaked;
            totalBets += s.betCount;
            unchecked { ++i; }
        }
    }
}
