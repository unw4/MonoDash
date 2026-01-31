// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title DelegatedSigner - EIP-712 typed data verification for off-chain bet signing
/// @notice Verifies off-chain signed bet orders for the session key flow.
contract DelegatedSigner {
    bytes32 public immutable DOMAIN_SEPARATOR;

    bytes32 public constant BET_ORDER_TYPEHASH =
        keccak256("BetOrder(address user,bytes32 eventId,uint8 outcomeIndex,uint128 amount,uint256 nonce,uint256 deadline)");

    mapping(address => uint256) public nonces;

    struct BetOrder {
        address user;
        bytes32 eventId;
        uint8 outcomeIndex;
        uint128 amount;
        uint256 nonce;
        uint256 deadline;
    }

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("MonoDash"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice Verify an EIP-712 signed bet order
    function verifyBetOrder(BetOrder calldata order, uint8 v, bytes32 r, bytes32 s)
        external
        view
        returns (address signer)
    {
        require(block.timestamp <= order.deadline, "DelegatedSigner: expired");

        bytes32 structHash = keccak256(
            abi.encode(
                BET_ORDER_TYPEHASH,
                order.user,
                order.eventId,
                order.outcomeIndex,
                order.amount,
                order.nonce,
                order.deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        signer = ecrecover(digest, v, r, s);
        require(signer != address(0), "DelegatedSigner: invalid signature");
    }

    /// @notice Consume a nonce (prevents replay)
    function useNonce(address user) external returns (uint256) {
        return nonces[user]++;
    }
}
