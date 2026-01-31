// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SessionKeyManager} from "../../src/account/SessionKeyManager.sol";
import {BettingEngine} from "../../src/core/BettingEngine.sol";
import {EventManager} from "../../src/core/EventManager.sol";
import {UserVault} from "../../src/core/UserVault.sol";
import {SettlementProcessor} from "../../src/core/SettlementProcessor.sol";
import {PythAdapter} from "../../src/oracle/PythAdapter.sol";
import {MockAura} from "../mocks/MockAura.sol";
import {MockPyth} from "../mocks/MockPyth.sol";

contract SessionKeyManagerTest is Test {
    SessionKeyManager public skm;
    BettingEngine public engine;
    EventManager public em;
    UserVault public vault;
    SettlementProcessor public settlement;
    MockAura public aura;
    MockPyth public mockPyth;
    PythAdapter public pythAdapter;

    address public keeper = makeAddr("keeper");
    address public alice = makeAddr("alice");
    address public ephKey = makeAddr("ephemeralKey");

    bytes32 public eventId;

    function setUp() public {
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
        settlement.setSettler(address(this), true);

        vm.deal(alice, 100 ether);
        vm.prank(alice);
        vault.deposit{value: 50 ether}();

        // Create event
        uint40 openTime = uint40(block.timestamp);
        vm.prank(keeper);
        eventId = em.createEvent(bytes32("feed1"), openTime, openTime + 15, 2, bytes32(0));
    }

    // ===================== AUTHORIZE SESSION KEY =====================

    function test_authorizeSessionKey() public {
        vm.prank(alice);
        skm.authorizeSessionKey(ephKey, uint40(block.timestamp + 3600), 10 ether, bytes32(0));

        assertTrue(skm.isValidSessionKey(alice, ephKey));
        assertEq(skm.getRemainingBudget(alice, ephKey), 10 ether);
    }

    function test_authorizeSessionKey_reverts_zeroAddress() public {
        vm.prank(alice);
        vm.expectRevert("SessionKey: zero address");
        skm.authorizeSessionKey(address(0), uint40(block.timestamp + 3600), 10 ether, bytes32(0));
    }

    function test_authorizeSessionKey_reverts_expired() public {
        vm.prank(alice);
        vm.expectRevert("SessionKey: already expired");
        skm.authorizeSessionKey(ephKey, uint40(block.timestamp - 1), 10 ether, bytes32(0));
    }

    // ===================== PLACE BET WITH SESSION KEY =====================

    function test_placeBetWithSessionKey() public {
        // Authorize
        vm.prank(alice);
        skm.authorizeSessionKey(ephKey, uint40(block.timestamp + 3600), 10 ether, bytes32(0));

        // Bet via ephemeral key
        vm.prank(ephKey);
        skm.placeBetWithSessionKey(alice, eventId, 0, 1 ether);

        // Verify bet recorded for alice
        assertEq(engine.getUserBet(alice, eventId).amount, 1 ether);
        assertEq(skm.getRemainingBudget(alice, ephKey), 9 ether);
    }

    function test_placeBetWithSessionKey_reverts_expired() public {
        vm.prank(alice);
        skm.authorizeSessionKey(ephKey, uint40(block.timestamp + 100), 10 ether, bytes32(0));

        vm.warp(block.timestamp + 200);

        vm.prank(ephKey);
        vm.expectRevert("SessionKey: expired");
        skm.placeBetWithSessionKey(alice, eventId, 0, 1 ether);
    }

    function test_placeBetWithSessionKey_reverts_spendLimit() public {
        vm.prank(alice);
        skm.authorizeSessionKey(ephKey, uint40(block.timestamp + 3600), 0.5 ether, bytes32(0));

        vm.prank(ephKey);
        vm.expectRevert("SessionKey: spend limit exceeded");
        skm.placeBetWithSessionKey(alice, eventId, 0, 1 ether);
    }

    function test_placeBetWithSessionKey_reverts_wrongEvent() public {
        // Restrict to specific event
        bytes32 otherEvent = keccak256("other");
        vm.prank(alice);
        skm.authorizeSessionKey(ephKey, uint40(block.timestamp + 3600), 10 ether, otherEvent);

        vm.prank(ephKey);
        vm.expectRevert("SessionKey: event not allowed");
        skm.placeBetWithSessionKey(alice, eventId, 0, 1 ether);
    }

    // ===================== REVOKE =====================

    function test_revokeSessionKey() public {
        vm.prank(alice);
        skm.authorizeSessionKey(ephKey, uint40(block.timestamp + 3600), 10 ether, bytes32(0));

        vm.prank(alice);
        skm.revokeSessionKey(ephKey);

        assertFalse(skm.isValidSessionKey(alice, ephKey));

        vm.prank(ephKey);
        vm.expectRevert("SessionKey: not active");
        skm.placeBetWithSessionKey(alice, eventId, 0, 1 ether);
    }
}
