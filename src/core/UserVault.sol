// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUserVault} from "../interfaces/IUserVault.sol";

/// @title UserVault - Per-user balance isolation for Monad parallel execution
/// @notice Each user's balance occupies a unique storage slot via mapping.
///         Deposits/withdrawals from different users execute fully in parallel.
/// @dev CRITICAL: No global counters. All state is per-user.
contract UserVault is IUserVault {
    // ===================== STORAGE =====================

    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _lockedBalances;
    mapping(address => bool) public authorizedEngines;
    address public owner;

    // ===================== MODIFIERS =====================

    modifier onlyOwner() {
        require(msg.sender == owner, "UserVault: not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(authorizedEngines[msg.sender], "UserVault: not authorized");
        _;
    }

    // ===================== CONSTRUCTOR =====================

    constructor() {
        owner = msg.sender;
    }

    // ===================== USER FUNCTIONS =====================

    /// @notice Deposit native tokens into vault
    function deposit() external payable {
        require(msg.value > 0, "UserVault: zero deposit");
        _balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw available (unlocked) balance
    function withdraw(uint256 amount) external {
        require(_balances[msg.sender] >= amount, "UserVault: insufficient balance");
        _balances[msg.sender] -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "UserVault: transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice View available and locked balances
    function getBalance(address user) external view returns (uint256 available, uint256 locked) {
        available = _balances[user];
        locked = _lockedBalances[user];
    }

    // ===================== ENGINE FUNCTIONS =====================

    /// @notice Lock funds for an active bet
    function lockBalance(address user, uint128 amount) external onlyAuthorized {
        require(_balances[user] >= amount, "UserVault: insufficient available");
        _balances[user] -= amount;
        _lockedBalances[user] += amount;
        emit BalanceLocked(user, amount);
    }

    /// @notice Unlock funds (bet voided or cancelled)
    function unlockBalance(address user, uint128 amount) external onlyAuthorized {
        require(_lockedBalances[user] >= amount, "UserVault: insufficient locked");
        _lockedBalances[user] -= amount;
        _balances[user] += amount;
        emit BalanceUnlocked(user, amount);
    }

    /// @notice Credit winnings to user's available balance
    function creditWinnings(address user, uint128 amount) external onlyAuthorized {
        _balances[user] += amount;
        emit BalanceCredited(user, amount);
    }

    /// @notice Deduct locked balance after settlement (losing bet)
    function deductLocked(address user, uint128 amount) external onlyAuthorized {
        require(_lockedBalances[user] >= amount, "UserVault: insufficient locked");
        _lockedBalances[user] -= amount;
    }

    // ===================== ADMIN =====================

    function setAuthorizedEngine(address engine, bool authorized) external onlyOwner {
        authorizedEngines[engine] = authorized;
    }
}
