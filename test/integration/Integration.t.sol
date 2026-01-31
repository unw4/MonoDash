// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {BettingEngine} from "../../src/core/BettingEngine.sol";
import {EventManager} from "../../src/core/EventManager.sol";
import {UserVault} from "../../src/core/UserVault.sol";
import {SettlementProcessor} from "../../src/core/SettlementProcessor.sol";
import {SessionKeyManager} from "../../src/account/SessionKeyManager.sol";
import {PythAdapter} from "../../src/oracle/PythAdapter.sol";
import {MockAura} from "../mocks/MockAura.sol";
import {MockPyth} from "../mocks/MockPyth.sol";
import {MicroEventLib} from "../../src/libraries/MicroEventLib.sol";

/// @title Integration tests for the full MonoDash betting lifecycle
contract IntegrationTest is Test {
    BettingEngine public engine;
    EventManager public em;
    UserVault public vault;
    SettlementProcessor public settlement;
    SessionKeyManager public skm;
    PythAdapter public pythAdapter;
    MockAura public aura;
    MockPyth public mockPyth;

    address public keeper = makeAddr("keeper");
    address public settler;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    function setUp() public {
        settler = address(this);

        aura = new MockAura();
        mockPyth = new MockPyth();
        pythAdapter = new PythAdapter(address(mockPyth));

        vault = new UserVault();
        em = new EventManager(address(aura));
        engine = new BettingEngine(address(em), address(vault));
        skm = new SessionKeyManager(address(engine));
        settlement = new SettlementProcessor(address(em), address(engine), address(pythAdapter));

        vault.setAuthorizedEngine(address(engine), true);
        em.setKeeper(keeper, true);
        em.setSettlementProcessor(address(settlement));
        engine.setSettlementProcessor(address(settlement));
        engine.setSessionKeyManager(address(skm));
        settlement.setSettler(settler, true);

        // Fund and deposit for all users
        address[3] memory users = [alice, bob, charlie];
        for (uint256 i = 0; i < users.length; i++) {
            vm.deal(users[i], 100 ether);
            vm.prank(users[i]);
            vault.deposit{value: 50 ether}();
        }
    }

    // ===================== FULL LIFECYCLE =====================

    /// @notice Complete happy path: deposit -> create event -> bet -> lock -> settle -> claim
    function test_fullLifecycle_depositBetSettleClaim() public {
        uint40 openTime = uint40(block.timestamp);
        uint40 closeTime = openTime + 10;

        // Keeper creates event
        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("match1"), openTime, closeTime, 2, bytes32(0));

        // Alice bets YES (0), Bob bets NO (1)
        vm.prank(alice);
        engine.placeBet(eventId, 0, 10 ether);

        vm.prank(bob);
        engine.placeBet(eventId, 1, 10 ether);

        // Verify pool totals
        assertEq(engine.getOutcomeTotal(eventId, 0), 10 ether);
        assertEq(engine.getOutcomeTotal(eventId, 1), 10 ether);

        // Time passes, lock event
        vm.warp(closeTime);
        em.lockEvent(eventId);

        // Settle: outcome 0 wins (Alice)
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = eventId;
        uint8[] memory outcomes = new uint8[](1);
        outcomes[0] = 0;

        settlement.settleBatch(ids, new bytes[](0), outcomes);

        // Alice claims winnings
        vm.prank(alice);
        engine.claimPayout(eventId);

        // Bob claims (loser)
        vm.prank(bob);
        engine.claimPayout(eventId);

        // Verify final balances
        // Alice: started with 50, bet 10, won proportional payout
        // Total pool = 20 ether, Alice's share = (10/10) * 20 = 20, fee = 0.4, net = 19.6
        // Alice final = 40 (after bet) + 19.6 = 59.6
        (uint256 aliceAvail, uint256 aliceLocked) = vault.getBalance(alice);
        assertEq(aliceAvail, 59.6 ether);
        assertEq(aliceLocked, 0);

        // Bob: started with 50, bet 10, lost
        (uint256 bobAvail, uint256 bobLocked) = vault.getBalance(bob);
        assertEq(bobAvail, 40 ether);
        assertEq(bobLocked, 0);
    }

    /// @notice Multiple users betting on the same event
    function test_fullLifecycle_multipleUsers() public {
        uint40 openTime = uint40(block.timestamp);

        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("match2"), openTime, openTime + 15, 2, bytes32(0));

        // Three users bet: Alice & Charlie on YES, Bob on NO
        vm.prank(alice);
        engine.placeBet(eventId, 0, 6 ether); // YES

        vm.prank(bob);
        engine.placeBet(eventId, 1, 12 ether); // NO

        vm.prank(charlie);
        engine.placeBet(eventId, 0, 4 ether); // YES

        // Pool: YES = 10, NO = 12, Total = 22
        assertEq(engine.getOutcomeTotal(eventId, 0), 10 ether);
        assertEq(engine.getOutcomeTotal(eventId, 1), 12 ether);

        // Lock and settle: YES wins
        vm.warp(openTime + 15);
        em.lockEvent(eventId);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = eventId;
        uint8[] memory outcomes = new uint8[](1);
        outcomes[0] = 0;
        settlement.settleBatch(ids, new bytes[](0), outcomes);

        // Alice claims: (6/10)*22 = 13.2 gross, fee = 0.264, net = 12.936
        vm.prank(alice);
        engine.claimPayout(eventId);

        // Charlie claims: (4/10)*22 = 8.8 gross, fee = 0.176, net = 8.624
        vm.prank(charlie);
        engine.claimPayout(eventId);

        // Bob claims (loser)
        vm.prank(bob);
        engine.claimPayout(eventId);

        (uint256 aliceAvail,) = vault.getBalance(alice);
        (uint256 charlieAvail,) = vault.getBalance(charlie);
        (uint256 bobAvail,) = vault.getBalance(bob);

        // Alice: 50 - 6 + 12.936 = 56.936
        assertEq(aliceAvail, 56.936 ether);
        // Charlie: 50 - 4 + 8.624 = 54.624
        assertEq(charlieAvail, 54.624 ether);
        // Bob: 50 - 12 = 38
        assertEq(bobAvail, 38 ether);
    }

    /// @notice Batch settlement of multiple events
    function test_fullLifecycle_batchSettlement() public {
        uint40 openTime = uint40(block.timestamp);

        bytes32[] memory eventIds = new bytes32[](5);
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(keeper);
            eventIds[i] = em.createEvent(bytes32(uint256(i + 100)), openTime, openTime + 10, 2, bytes32(0));

            vm.prank(alice);
            engine.placeBet(eventIds[i], 0, 1 ether);

            vm.prank(bob);
            engine.placeBet(eventIds[i], 1, 1 ether);
        }

        vm.warp(openTime + 10);
        for (uint256 i = 0; i < 5; i++) {
            em.lockEvent(eventIds[i]);
        }

        // Batch settle all 5
        uint8[] memory outcomes = new uint8[](5);
        for (uint256 i = 0; i < 5; i++) {
            outcomes[i] = uint8(i % 2); // Alternating winners
        }

        settlement.settleBatch(eventIds, new bytes[](0), outcomes);

        // Verify all settled
        for (uint256 i = 0; i < 5; i++) {
            (,,, MicroEventLib.EventStatus status,,,,,) = em.getEvent(eventIds[i]);
            assertTrue(status == MicroEventLib.EventStatus.SETTLED);
        }
    }

    /// @notice Session key flow: authorize -> bet via key -> settle -> claim
    function test_fullLifecycle_sessionKeyFlow() public {
        address ephKey = makeAddr("tempKey");
        uint40 openTime = uint40(block.timestamp);

        // Create event
        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("skf"), openTime, openTime + 15, 2, bytes32(0));

        // Alice authorizes session key
        vm.prank(alice);
        skm.authorizeSessionKey(ephKey, uint40(block.timestamp + 3600), 20 ether, bytes32(0));

        // Ephemeral key places bet on behalf of Alice
        vm.prank(ephKey);
        skm.placeBetWithSessionKey(alice, eventId, 0, 5 ether);

        // Verify bet recorded under Alice
        assertEq(engine.getUserBet(alice, eventId).amount, 5 ether);

        // Bob bets directly
        vm.prank(bob);
        engine.placeBet(eventId, 1, 5 ether);

        // Settle
        vm.warp(openTime + 15);
        em.lockEvent(eventId);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = eventId;
        uint8[] memory o = new uint8[](1);
        o[0] = 0; // Alice wins

        settlement.settleBatch(ids, new bytes[](0), o);

        // Alice claims
        vm.prank(alice);
        engine.claimPayout(eventId);

        (uint256 aliceAvail,) = vault.getBalance(alice);
        // 50 - 5 + (5/5)*10*0.98 = 45 + 9.8 = 54.8
        assertEq(aliceAvail, 54.8 ether);
    }

    /// @notice Void and refund flow
    function test_fullLifecycle_voidAndRefund() public {
        uint40 openTime = uint40(block.timestamp);

        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("void"), openTime, openTime + 10, 2, bytes32(0));

        vm.prank(alice);
        engine.placeBet(eventId, 0, 8 ether);

        vm.prank(bob);
        engine.placeBet(eventId, 1, 12 ether);

        // Void the event (e.g., oracle failure)
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = eventId;
        settlement.voidBatch(ids);

        // Both users claim refund
        vm.prank(alice);
        engine.claimPayout(eventId);

        vm.prank(bob);
        engine.claimPayout(eventId);

        // Full refunds
        (uint256 aliceAvail,) = vault.getBalance(alice);
        (uint256 bobAvail,) = vault.getBalance(bob);

        assertEq(aliceAvail, 50 ether);
        assertEq(bobAvail, 50 ether);
    }
}
