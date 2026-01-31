// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {UserVault} from "../src/core/UserVault.sol";
import {EventManager} from "../src/core/EventManager.sol";
import {BettingEngine} from "../src/core/BettingEngine.sol";
import {SettlementProcessor} from "../src/core/SettlementProcessor.sol";
import {SessionKeyManager} from "../src/account/SessionKeyManager.sol";
import {DelegatedSigner} from "../src/account/DelegatedSigner.sol";
import {PythAdapter} from "../src/oracle/PythAdapter.sol";
import {AuraVerifier} from "../src/oracle/AuraVerifier.sol";

/// @title MonoDash Deployment Script
/// @notice Deploys all contracts in dependency order and wires them together
contract DeployMonoDash is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address pythContract = vm.envAddress("PYTH_CONTRACT");

        vm.startBroadcast(deployerKey);

        // 1. Deploy independent contracts
        AuraVerifier aura = new AuraVerifier();
        PythAdapter pythAdapter = new PythAdapter(pythContract);
        UserVault vault = new UserVault();
        DelegatedSigner delegatedSigner = new DelegatedSigner();

        // 2. Deploy EventManager (depends on AuraVerifier)
        EventManager eventManager = new EventManager(address(aura));

        // 3. Deploy BettingEngine (depends on EventManager + UserVault)
        BettingEngine engine = new BettingEngine(address(eventManager), address(vault));

        // 4. Deploy SessionKeyManager (depends on BettingEngine)
        SessionKeyManager sessionKeyMgr = new SessionKeyManager(address(engine));

        // 5. Deploy SettlementProcessor (depends on EventManager + BettingEngine + PythAdapter)
        SettlementProcessor settlement =
            new SettlementProcessor(address(eventManager), address(engine), address(pythAdapter));

        // 6. Wire up cross-references
        vault.setAuthorizedEngine(address(engine), true);
        eventManager.setSettlementProcessor(address(settlement));
        engine.setSettlementProcessor(address(settlement));
        engine.setSessionKeyManager(address(sessionKeyMgr));

        // 7. Set up initial keepers/settlers (deployer)
        address deployer = vm.addr(deployerKey);
        eventManager.setKeeper(deployer, true);
        settlement.setSettler(deployer, true);

        vm.stopBroadcast();

        // Log deployed addresses
        console.log("=== MonoDash Deployed ===");
        console.log("AuraVerifier:        ", address(aura));
        console.log("PythAdapter:         ", address(pythAdapter));
        console.log("UserVault:           ", address(vault));
        console.log("DelegatedSigner:     ", address(delegatedSigner));
        console.log("EventManager:        ", address(eventManager));
        console.log("BettingEngine:       ", address(engine));
        console.log("SessionKeyManager:   ", address(sessionKeyMgr));
        console.log("SettlementProcessor: ", address(settlement));
    }
}
