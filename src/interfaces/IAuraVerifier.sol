// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAuraVerifier {
    event AttestationVerified(bytes32 indexed attestationHash, address indexed verifier);
    event ModelRegistered(bytes32 indexed modelHash, string modelUri);

    /// @notice Verify an AI provenance attestation
    function verifyAttestation(
        bytes32 modelHash,
        bytes32 dataHash,
        uint64 confidence,
        bytes calldata signature
    ) external returns (bytes32 attestationHash);

    /// @notice Check if a model is registered and trusted
    function isModelRegistered(bytes32 modelHash) external view returns (bool);

    /// @notice Get minimum confidence threshold
    function minConfidence() external view returns (uint64);
}
