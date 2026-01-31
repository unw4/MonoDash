// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {BettingEngine} from "../../src/core/BettingEngine.sol";
import {EventManager} from "../../src/core/EventManager.sol";
import {UserVault} from "../../src/core/UserVault.sol";
import {SettlementProcessor} from "../../src/core/SettlementProcessor.sol";
import {PythAdapter} from "../../src/oracle/PythAdapter.sol";
import {MockAura} from "../mocks/MockAura.sol";
import {MockPyth} from "../mocks/MockPyth.sol";
import {ShardLib} from "../../src/libraries/ShardLib.sol";
import {BetLib} from "../../src/libraries/BetLib.sol";
import {MicroEventLib} from "../../src/libraries/MicroEventLib.sol";

contract BettingEngineTest is Test {
    BettingEngine public engine;
    EventManager public em;
    UserVault public vault;
    SettlementProcessor public settlement;
    PythAdapter public pythAdapter;
    MockAura public aura;
    MockPyth public mockPyth;

    address public keeper = makeAddr("keeper");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    bytes32 public eventId;

    function setUp() public {
        // Deploy mock oracle
        aura = new MockAura();
        mockPyth = new MockPyth();
        pythAdapter = new PythAdapter(address(mockPyth));

        // Deploy core contracts
        vault = new UserVault();
        em = new EventManager(address(aura));
        engine = new BettingEngine(address(em), address(vault));

        // Deploy settlement
        settlement = new SettlementProcessor(address(em), address(engine), address(pythAdapter));

        // Wire up
        vault.setAuthorizedEngine(address(engine), true);
        em.setKeeper(keeper, true);
        em.setSettlementProcessor(address(settlement));
        engine.setSettlementProcessor(address(settlement));
        settlement.setSettler(address(this), true);

        // Fund users
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);

        // Deposit into vault
        vm.prank(alice);
        vault.deposit{value: 50 ether}();
        vm.prank(bob);
        vault.deposit{value: 50 ether}();
        vm.prank(charlie);
        vault.deposit{value: 50 ether}();

        // Create a test event
        uint40 openTime = uint40(block.timestamp);
        uint40 closeTime = openTime + 15;
        vm.prank(keeper);
        eventId = em.createEvent(bytes32("feed1"), openTime, closeTime, 2, bytes32(0));
    }

    // ===================== PLACE BET =====================

    function test_placeBet_success() public {
        vm.prank(alice);
        engine.placeBet(eventId, 0, 1 ether);

        BetLib.UserBet memory bet = engine.getUserBet(alice, eventId);
        assertEq(bet.amount, 1 ether);
        assertEq(bet.outcomeIndex, 0);
        assertFalse(bet.settled);
    }

    function test_placeBet_updatesPoolShard() public {
        vm.prank(alice);
        engine.placeBet(eventId, 0, 2 ether);

        uint128 total = engine.getOutcomeTotal(eventId, 0);
        assertEq(total, 2 ether);
    }

    function test_placeBet_locksBalance() public {
        vm.prank(alice);
        engine.placeBet(eventId, 0, 5 ether);

        (uint256 available, uint256 locked) = vault.getBalance(alice);
        assertEq(available, 45 ether);
        assertEq(locked, 5 ether);
    }

    function test_placeBet_reverts_notAccepting() public {
        bytes32 fakeEvent = keccak256("nonexistent");
        vm.prank(alice);
        vm.expectRevert("BettingEngine: not accepting bets");
        engine.placeBet(fakeEvent, 0, 1 ether);
    }

    function test_placeBet_reverts_alreadyBet() public {
        vm.prank(alice);
        engine.placeBet(eventId, 0, 1 ether);

        vm.prank(alice);
        vm.expectRevert("BettingEngine: already bet");
        engine.placeBet(eventId, 1, 1 ether);
    }

    function test_placeBet_reverts_betTooSmall() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BetLib.BetTooSmall.selector, uint128(0.0001 ether)));
        engine.placeBet(eventId, 0, 0.0001 ether);
    }

    function test_placeBet_reverts_invalidOutcome() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BetLib.InvalidOutcome.selector, uint8(5), uint8(2)));
        engine.placeBet(eventId, 5, 1 ether);
    }

    // ===================== MULTIPLE USERS =====================

    function test_multipleUsers_sameSide() public {
        vm.prank(alice);
        engine.placeBet(eventId, 0, 3 ether);

        vm.prank(bob);
        engine.placeBet(eventId, 0, 7 ether);

        uint128 total = engine.getOutcomeTotal(eventId, 0);
        assertEq(total, 10 ether);
    }

    function test_multipleUsers_differentSides() public {
        vm.prank(alice);
        engine.placeBet(eventId, 0, 5 ether);

        vm.prank(bob);
        engine.placeBet(eventId, 1, 5 ether);

        assertEq(engine.getOutcomeTotal(eventId, 0), 5 ether);
        assertEq(engine.getOutcomeTotal(eventId, 1), 5 ether);
    }

    // ===================== SHARD ASSIGNMENT =====================

    function test_shardIndex_deterministic() public pure {
        address user1 = address(0x1234);
        address user2 = address(0x5678);

        uint8 shard1 = ShardLib.shardIndex(user1);
        uint8 shard2 = ShardLib.shardIndex(user2);

        // Shards derived from last 4 bits
        assertEq(shard1, uint8(uint160(user1) & 0x0F));
        assertEq(shard2, uint8(uint160(user2) & 0x0F));
        assertTrue(shard1 < 16);
        assertTrue(shard2 < 16);
    }

    // ===================== SETTLEMENT + CLAIM =====================

    function test_claimPayout_winner() public {
        // Alice bets YES (outcome 0), Bob bets NO (outcome 1)
        vm.prank(alice);
        engine.placeBet(eventId, 0, 5 ether);

        vm.prank(bob);
        engine.placeBet(eventId, 1, 5 ether);

        // Close and lock event
        vm.warp(block.timestamp + 15);
        em.lockEvent(eventId);

        // Settle: outcome 0 wins (Alice wins)
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = eventId;
        bytes[] memory priceData = new bytes[](0);
        uint8[] memory outcomes = new uint8[](1);
        outcomes[0] = 0;

        settlement.settleBatch(ids, priceData, outcomes);

        // Alice claims: gets proportional payout - 2% fee
        // Total pool = 10 ether, Alice staked 5/5 of winning side
        // Gross payout = (5/5) * 10 = 10 ether
        // Fee = 10 * 0.02 = 0.2 ether
        // Net = 9.8 ether
        uint256 aliceBalBefore;
        (aliceBalBefore,) = vault.getBalance(alice);

        vm.prank(alice);
        engine.claimPayout(eventId);

        (uint256 aliceAvail,) = vault.getBalance(alice);
        // Alice had 45 ether available (50 - 5 bet), now gets 9.8 ether credited
        assertEq(aliceAvail, aliceBalBefore + 9.8 ether);
    }

    function test_claimPayout_loser() public {
        vm.prank(alice);
        engine.placeBet(eventId, 0, 5 ether);

        vm.prank(bob);
        engine.placeBet(eventId, 1, 5 ether);

        vm.warp(block.timestamp + 15);
        em.lockEvent(eventId);

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = eventId;
        bytes[] memory priceData = new bytes[](0);
        uint8[] memory outcomes = new uint8[](1);
        outcomes[0] = 0; // Alice wins

        settlement.settleBatch(ids, priceData, outcomes);

        // Bob is the loser
        vm.prank(bob);
        engine.claimPayout(eventId);

        (uint256 bobAvail, uint256 bobLocked) = vault.getBalance(bob);
        assertEq(bobAvail, 45 ether); // 50 - 5 bet, no winnings
        assertEq(bobLocked, 0);
    }

    function test_claimPayout_voided() public {
        vm.prank(alice);
        engine.placeBet(eventId, 0, 5 ether);

        // Void the event
        settlement.voidBatch(_wrapSingle(eventId));

        vm.prank(alice);
        engine.claimPayout(eventId);

        (uint256 available, uint256 locked) = vault.getBalance(alice);
        assertEq(available, 50 ether); // Full refund
        assertEq(locked, 0);
    }

    function test_claimPayout_reverts_noBet() public {
        vm.prank(charlie); // Charlie didn't bet
        vm.expectRevert("BettingEngine: no bet");
        engine.claimPayout(eventId);
    }

    function test_claimPayout_reverts_alreadySettled() public {
        vm.prank(alice);
        engine.placeBet(eventId, 0, 1 ether);

        // Void and claim
        settlement.voidBatch(_wrapSingle(eventId));
        vm.prank(alice);
        engine.claimPayout(eventId);

        // Try to claim again
        vm.prank(alice);
        vm.expectRevert("BettingEngine: already settled");
        engine.claimPayout(eventId);
    }

    // ===================== HELPERS =====================

    function _wrapSingle(bytes32 id) internal pure returns (bytes32[] memory) {
        bytes32[] memory arr = new bytes32[](1);
        arr[0] = id;
        return arr;
    }
}
