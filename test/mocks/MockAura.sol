// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAuraVerifier} from "../../src/interfaces/IAuraVerifier.sol";

/// @title MockAura - Mock AI provenance verifier for testing
contract MockAura is IAuraVerifier {
    mapping(bytes32 => bool) private _registeredModels;
    uint64 public override minConfidence = 7000;

    function verifyAttestation(bytes32, bytes32, uint64, bytes calldata)
        external
        pure
        returns (bytes32)
    {
        return keccak256("mock_attestation");
    }

    function isModelRegistered(bytes32 modelHash) external view returns (bool) {
        return _registeredModels[modelHash];
    }

    function registerModel(bytes32 modelHash) external {
        _registeredModels[modelHash] = true;
    }
}
