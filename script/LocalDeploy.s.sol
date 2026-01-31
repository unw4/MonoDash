// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {UserVault} from "../src/core/UserVault.sol";
import {EventManager} from "../src/core/EventManager.sol";
import {BettingEngine} from "../src/core/BettingEngine.sol";
import {SettlementProcessor} from "../src/core/SettlementProcessor.sol";
import {SessionKeyManager} from "../src/account/SessionKeyManager.sol";
import {PythAdapter} from "../src/oracle/PythAdapter.sol";
import {AuraVerifier} from "../src/oracle/AuraVerifier.sol";

/// @notice Deploys to local Anvil for frontend testing
contract LocalDeploy is Script {
    function run() external {
        // Anvil default private key #0
        uint256 deployerKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // Deploy mock Pyth (simple contract that does nothing)
        MockPythLocal mockPyth = new MockPythLocal();

        // Deploy
        AuraVerifier aura = new AuraVerifier();
        PythAdapter pythAdapter = new PythAdapter(address(mockPyth));
        UserVault vault = new UserVault();
        EventManager eventManager = new EventManager(address(aura));
        BettingEngine engine = new BettingEngine(address(eventManager), address(vault));
        SessionKeyManager skm = new SessionKeyManager(address(engine));
        SettlementProcessor settlement = new SettlementProcessor(
            address(eventManager), address(engine), address(pythAdapter)
        );

        // Wire
        vault.setAuthorizedEngine(address(engine), true);
        eventManager.setSettlementProcessor(address(settlement));
        engine.setSettlementProcessor(address(settlement));
        engine.setSessionKeyManager(address(skm));
        eventManager.setKeeper(deployer, true);
        settlement.setSettler(deployer, true);

        vm.stopBroadcast();

        // Output JS setup command
        console.log("");
        console.log("=== MonoDash Local Deploy ===");
        console.log("");
        console.log("Paste this in browser console:");
        console.log("");
        string memory cmd = string.concat(
            "setAddresses('",
            vm.toString(address(vault)), "','",
            vm.toString(address(eventManager)), "','",
            vm.toString(address(engine)), "','",
            vm.toString(address(settlement)), "')"
        );
        console.log(cmd);
        console.log("");
    }
}

/// @dev Minimal mock for local testing
contract MockPythLocal {
    function getUpdateFee(bytes[] calldata) external pure returns (uint256) { return 0; }
    function updatePriceFeeds(bytes[] calldata) external payable {}
    function getPriceNoOlderThan(bytes32, uint256) external view returns (int64, uint64, int32, uint256) {
        return (100000, 50, -5, block.timestamp);
    }
}
