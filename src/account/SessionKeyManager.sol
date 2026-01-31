// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IBettingEngine} from "../interfaces/IBettingEngine.sol";

/// @title SessionKeyManager - Ephemeral session keys for seamless betting UX
/// @notice User signs ONE tx to authorize an ephemeral key.
///         All subsequent bets use the ephemeral key -> no wallet popup.
/// @dev PARALLELISM: sessionKeys[owner][key] is per-user per-key -> parallel safe.
contract SessionKeyManager {
    // ===================== TYPES =====================

    struct SessionKey {
        uint40 expiry;
        uint128 spendLimit;
        uint128 spent;
        bytes32 allowedEventId; // 0 = any event
        bool active;
    }

    // ===================== STORAGE =====================

    mapping(address => mapping(address => SessionKey)) public sessionKeys;
    IBettingEngine public immutable bettingEngine;

    // ===================== EVENTS =====================

    event SessionKeyAuthorized(
        address indexed owner, address indexed ephemeralKey, uint40 expiry, uint128 spendLimit
    );
    event SessionKeyRevoked(address indexed owner, address indexed ephemeralKey);
    event DelegatedBetPlaced(address indexed owner, address indexed ephemeralKey, bytes32 indexed eventId);

    // ===================== CONSTRUCTOR =====================

    constructor(address _bettingEngine) {
        bettingEngine = IBettingEngine(_bettingEngine);
    }

    // ===================== USER FUNCTIONS =====================

    /// @notice Authorize an ephemeral session key (user signs this ONE tx)
    function authorizeSessionKey(
        address ephemeralKey,
        uint40 expiry,
        uint128 spendLimit,
        bytes32 allowedEventId
    ) external {
        require(ephemeralKey != address(0), "SessionKey: zero address");
        require(expiry > block.timestamp, "SessionKey: already expired");
        require(spendLimit > 0, "SessionKey: zero limit");

        sessionKeys[msg.sender][ephemeralKey] = SessionKey({
            expiry: expiry,
            spendLimit: spendLimit,
            spent: 0,
            allowedEventId: allowedEventId,
            active: true
        });

        emit SessionKeyAuthorized(msg.sender, ephemeralKey, expiry, spendLimit);
    }

    /// @notice Revoke a session key
    function revokeSessionKey(address ephemeralKey) external {
        sessionKeys[msg.sender][ephemeralKey].active = false;
        emit SessionKeyRevoked(msg.sender, ephemeralKey);
    }

    // ===================== DELEGATED BETTING =====================

    /// @notice Place a bet using a session key
    /// @dev msg.sender is the ephemeral key
    function placeBetWithSessionKey(
        address betOwner,
        bytes32 eventId,
        uint8 outcomeIndex,
        uint128 amount
    ) external {
        SessionKey storage sk = sessionKeys[betOwner][msg.sender];

        require(sk.active, "SessionKey: not active");
        require(block.timestamp < sk.expiry, "SessionKey: expired");
        require(sk.spent + amount <= sk.spendLimit, "SessionKey: spend limit exceeded");

        if (sk.allowedEventId != bytes32(0)) {
            require(sk.allowedEventId == eventId, "SessionKey: event not allowed");
        }

        sk.spent += amount;

        bettingEngine.placeBetDelegated(betOwner, eventId, outcomeIndex, amount);

        emit DelegatedBetPlaced(betOwner, msg.sender, eventId);
    }

    // ===================== VIEW =====================

    function isValidSessionKey(address keyOwner, address key) external view returns (bool) {
        SessionKey storage sk = sessionKeys[keyOwner][key];
        return sk.active && block.timestamp < sk.expiry && sk.spent < sk.spendLimit;
    }

    function getRemainingBudget(address keyOwner, address key) external view returns (uint128) {
        SessionKey storage sk = sessionKeys[keyOwner][key];
        if (!sk.active || block.timestamp >= sk.expiry) return 0;
        return sk.spendLimit - sk.spent;
    }
}
