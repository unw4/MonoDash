// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title BetLib - Bet validation and payout calculation
/// @notice Proportional payout model with 2% house fee.
library BetLib {
    uint128 internal constant MIN_BET = 0.001 ether;
    uint128 internal constant MAX_BET = 100 ether;
    uint16 internal constant HOUSE_FEE_BPS = 200;
    uint16 internal constant BPS_DENOMINATOR = 10000;

    struct UserBet {
        uint128 amount;
        uint8 outcomeIndex;
        uint40 timestamp;
        bool settled;
    }

    error BetTooSmall(uint128 amount);
    error BetTooLarge(uint128 amount);
    error InvalidOutcome(uint8 outcome, uint8 maxOutcomes);
    error AlreadyBet(address user, bytes32 eventId);
    error BetNotSettled(address user, bytes32 eventId);

    /// @notice Validate bet parameters
    function validateBet(
        uint128 amount,
        uint8 outcomeIndex,
        uint8 numOutcomes
    ) internal pure {
        if (amount < MIN_BET) revert BetTooSmall(amount);
        if (amount > MAX_BET) revert BetTooLarge(amount);
        if (outcomeIndex >= numOutcomes) revert InvalidOutcome(outcomeIndex, numOutcomes);
    }

    /// @notice Calculate payout for a winning bet
    /// @dev payout = (userStake / winningPoolTotal) * totalPool * (1 - fee)
    function calculatePayout(
        uint128 userStake,
        uint128 winningOutcomeTotal,
        uint128 totalPoolAllOutcomes
    ) internal pure returns (uint128 payout, uint128 fee) {
        if (winningOutcomeTotal == 0) return (0, 0);

        uint256 grossPayout = (uint256(userStake) * uint256(totalPoolAllOutcomes))
            / uint256(winningOutcomeTotal);

        fee = uint128((grossPayout * HOUSE_FEE_BPS) / BPS_DENOMINATOR);
        payout = uint128(grossPayout - fee);
    }
}
