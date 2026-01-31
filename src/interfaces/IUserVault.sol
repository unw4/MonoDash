// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IUserVault {
    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event BalanceLocked(address indexed user, uint256 amount);
    event BalanceUnlocked(address indexed user, uint256 amount);
    event BalanceCredited(address indexed user, uint256 amount);

    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function getBalance(address user) external view returns (uint256 available, uint256 locked);

    /// @notice Lock funds for an active bet (BettingEngine only)
    function lockBalance(address user, uint128 amount) external;
    /// @notice Unlock funds when bet is voided/cancelled (BettingEngine only)
    function unlockBalance(address user, uint128 amount) external;
    /// @notice Credit winnings to available balance (BettingEngine only)
    function creditWinnings(address user, uint128 amount) external;
    /// @notice Deduct locked balance after settlement loss (BettingEngine only)
    function deductLocked(address user, uint128 amount) external;
}
