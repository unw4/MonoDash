// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {EventManager} from "../../src/core/EventManager.sol";
import {MicroEventLib} from "../../src/libraries/MicroEventLib.sol";
import {MockAura} from "../mocks/MockAura.sol";

contract EventManagerTest is Test {
    EventManager public em;
    MockAura public aura;

    address public keeper = makeAddr("keeper");
    address public settler = makeAddr("settler");
    address public nobody = makeAddr("nobody");

    function setUp() public {
        aura = new MockAura();
        em = new EventManager(address(aura));
        em.setKeeper(keeper, true);
        em.setSettlementProcessor(settler);
    }

    // ===================== CREATE EVENT =====================

    function test_createEvent_success() public {
        uint40 openTime = uint40(block.timestamp);
        uint40 closeTime = openTime + 10;

        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("feed1"), openTime, closeTime, 2, bytes32(0));

        (
            uint40 ot, uint40 ct, uint40 st,
            MicroEventLib.EventStatus status, uint8 numOutcomes,
            address creator, bytes32 priceFeedId, uint8 winningOutcome,
            bytes32 auraAttestation
        ) = em.getEvent(eventId);

        assertEq(ot, openTime);
        assertEq(ct, closeTime);
        assertEq(st, 0);
        assertTrue(status == MicroEventLib.EventStatus.OPEN);
        assertEq(numOutcomes, 2);
        assertEq(creator, keeper);
        assertEq(priceFeedId, bytes32("feed1"));
    }

    function test_createEvent_reverts_notKeeper() public {
        uint40 openTime = uint40(block.timestamp);
        vm.prank(nobody);
        vm.expectRevert("EventManager: not keeper");
        em.createEvent(bytes32("feed1"), openTime, openTime + 10, 2, bytes32(0));
    }

    function test_createEvent_reverts_invalidWindow_tooShort() public {
        uint40 openTime = uint40(block.timestamp);
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(MicroEventLib.InvalidWindow.selector, uint40(2)));
        em.createEvent(bytes32("feed1"), openTime, openTime + 2, 2, bytes32(0));
    }

    function test_createEvent_reverts_invalidWindow_tooLong() public {
        uint40 openTime = uint40(block.timestamp);
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(MicroEventLib.InvalidWindow.selector, uint40(60)));
        em.createEvent(bytes32("feed1"), openTime, openTime + 60, 2, bytes32(0));
    }

    function test_createEvent_reverts_invalidOutcomes() public {
        uint40 openTime = uint40(block.timestamp);
        vm.prank(keeper);
        vm.expectRevert("EventManager: invalid outcomes");
        em.createEvent(bytes32("feed1"), openTime, openTime + 10, 1, bytes32(0));
    }

    // ===================== LOCK EVENT =====================

    function test_lockEvent_success() public {
        uint40 openTime = uint40(block.timestamp);
        uint40 closeTime = openTime + 10;

        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("feed1"), openTime, closeTime, 2, bytes32(0));

        // Advance time past closeTime
        vm.warp(closeTime);
        em.lockEvent(eventId);

        (,,, MicroEventLib.EventStatus status,,,,,) = em.getEvent(eventId);
        assertTrue(status == MicroEventLib.EventStatus.LOCKED);
    }

    function test_lockEvent_reverts_tooEarly() public {
        uint40 openTime = uint40(block.timestamp);
        uint40 closeTime = openTime + 10;

        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("feed1"), openTime, closeTime, 2, bytes32(0));

        vm.expectRevert("EventManager: window still open");
        em.lockEvent(eventId);
    }

    // ===================== SETTLE EVENT =====================

    function test_settleEvent_success() public {
        uint40 openTime = uint40(block.timestamp);
        uint40 closeTime = openTime + 10;

        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("feed1"), openTime, closeTime, 2, bytes32(0));

        vm.warp(closeTime);
        em.lockEvent(eventId);

        vm.prank(settler);
        em.settleEvent(eventId, 0);

        (,,, MicroEventLib.EventStatus status,,,, uint8 winningOutcome,) = em.getEvent(eventId);
        assertTrue(status == MicroEventLib.EventStatus.SETTLED);
        assertEq(winningOutcome, 0);
    }

    function test_settleEvent_reverts_notSettlement() public {
        uint40 openTime = uint40(block.timestamp);
        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("feed1"), openTime, openTime + 10, 2, bytes32(0));

        vm.warp(openTime + 10);
        em.lockEvent(eventId);

        vm.prank(nobody);
        vm.expectRevert("EventManager: not settlement");
        em.settleEvent(eventId, 0);
    }

    // ===================== VOID EVENT =====================

    function test_voidEvent_success_fromOpen() public {
        uint40 openTime = uint40(block.timestamp);
        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("feed1"), openTime, openTime + 10, 2, bytes32(0));

        vm.prank(settler);
        em.voidEvent(eventId);

        (,,, MicroEventLib.EventStatus status,,,,,) = em.getEvent(eventId);
        assertTrue(status == MicroEventLib.EventStatus.VOIDED);
    }

    function test_voidEvent_success_fromLocked() public {
        uint40 openTime = uint40(block.timestamp);
        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("feed1"), openTime, openTime + 10, 2, bytes32(0));

        vm.warp(openTime + 10);
        em.lockEvent(eventId);

        vm.prank(settler);
        em.voidEvent(eventId);

        (,,, MicroEventLib.EventStatus status,,,,,) = em.getEvent(eventId);
        assertTrue(status == MicroEventLib.EventStatus.VOIDED);
    }

    // ===================== IS ACCEPTING BETS =====================

    function test_isAcceptingBets() public {
        uint40 openTime = uint40(block.timestamp);
        uint40 closeTime = openTime + 10;

        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("feed1"), openTime, closeTime, 2, bytes32(0));

        assertTrue(em.isAcceptingBets(eventId));

        // After close time
        vm.warp(closeTime);
        assertFalse(em.isAcceptingBets(eventId));
    }

    // ===================== FULL LIFECYCLE =====================

    function test_fullLifecycle() public {
        uint40 openTime = uint40(block.timestamp);
        uint40 closeTime = openTime + 15;

        // Create
        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("feed1"), openTime, closeTime, 3, bytes32(0));

        // Verify OPEN
        (,,, MicroEventLib.EventStatus s1,,,,,) = em.getEvent(eventId);
        assertTrue(s1 == MicroEventLib.EventStatus.OPEN);

        // Lock
        vm.warp(closeTime);
        em.lockEvent(eventId);

        (,,, MicroEventLib.EventStatus s2,,,,,) = em.getEvent(eventId);
        assertTrue(s2 == MicroEventLib.EventStatus.LOCKED);

        // Settle
        vm.prank(settler);
        em.settleEvent(eventId, 1);

        (,,, MicroEventLib.EventStatus s3,,,, uint8 winner,) = em.getEvent(eventId);
        assertTrue(s3 == MicroEventLib.EventStatus.SETTLED);
        assertEq(winner, 1);
    }
}
