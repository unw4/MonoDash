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
import {MicroEventLib} from "../../src/libraries/MicroEventLib.sol";

contract SettlementProcessorTest is Test {
    BettingEngine public engine;
    EventManager public em;
    UserVault public vault;
    SettlementProcessor public settlement;
    PythAdapter public pythAdapter;
    MockAura public aura;
    MockPyth public mockPyth;

    address public keeper = makeAddr("keeper");
    address public settler = makeAddr("settler");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        aura = new MockAura();
        mockPyth = new MockPyth();
        pythAdapter = new PythAdapter(address(mockPyth));

        vault = new UserVault();
        em = new EventManager(address(aura));
        engine = new BettingEngine(address(em), address(vault));
        settlement = new SettlementProcessor(address(em), address(engine), address(pythAdapter));

        vault.setAuthorizedEngine(address(engine), true);
        em.setKeeper(keeper, true);
        em.setSettlementProcessor(address(settlement));
        engine.setSettlementProcessor(address(settlement));
        settlement.setSettler(settler, true);

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        vm.prank(alice);
        vault.deposit{value: 50 ether}();
        vm.prank(bob);
        vault.deposit{value: 50 ether}();
    }

    function test_settleBatch_single() public {
        // Create and populate event
        uint40 openTime = uint40(block.timestamp);
        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("feed1"), openTime, openTime + 10, 2, bytes32(0));

        vm.prank(alice);
        engine.placeBet(eventId, 0, 1 ether);

        // Lock
        vm.warp(openTime + 10);
        em.lockEvent(eventId);

        // Settle
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = eventId;
        uint8[] memory outcomes = new uint8[](1);
        outcomes[0] = 0;

        vm.prank(settler);
        settlement.settleBatch(ids, new bytes[](0), outcomes);

        assertTrue(settlement.isSettleable(eventId) == false);
    }

    function test_settleBatch_multiple() public {
        uint40 openTime = uint40(block.timestamp);

        // Create 3 events
        bytes32[] memory eventIds = new bytes32[](3);
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(keeper);
            eventIds[i] = em.createEvent(
                bytes32(uint256(i + 1)),
                openTime,
                openTime + 10,
                2,
                bytes32(0)
            );

            vm.prank(alice);
            engine.placeBet(eventIds[i], 0, 1 ether);
        }

        // Lock all
        vm.warp(openTime + 10);
        for (uint256 i = 0; i < 3; i++) {
            em.lockEvent(eventIds[i]);
        }

        // Settle batch
        uint8[] memory outcomes = new uint8[](3);
        outcomes[0] = 0;
        outcomes[1] = 1;
        outcomes[2] = 0;

        vm.prank(settler);
        settlement.settleBatch(eventIds, new bytes[](0), outcomes);

        // Verify all settled
        for (uint256 i = 0; i < 3; i++) {
            (,,, MicroEventLib.EventStatus status,,,,,) = em.getEvent(eventIds[i]);
            assertTrue(status == MicroEventLib.EventStatus.SETTLED);
        }
    }

    function test_settleBatch_reverts_unauthorized() public {
        vm.prank(alice);
        vm.expectRevert("Settlement: not authorized");
        settlement.settleBatch(new bytes32[](0), new bytes[](0), new uint8[](0));
    }

    function test_settleBatch_reverts_lengthMismatch() public {
        bytes32[] memory ids = new bytes32[](2);
        uint8[] memory outcomes = new uint8[](1);

        vm.prank(settler);
        vm.expectRevert("Settlement: length mismatch");
        settlement.settleBatch(ids, new bytes[](0), outcomes);
    }

    function test_voidBatch() public {
        uint40 openTime = uint40(block.timestamp);

        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("feed1"), openTime, openTime + 10, 2, bytes32(0));

        bytes32[] memory ids = new bytes32[](1);
        ids[0] = eventId;

        vm.prank(settler);
        settlement.voidBatch(ids);

        (,,, MicroEventLib.EventStatus status,,,,,) = em.getEvent(eventId);
        assertTrue(status == MicroEventLib.EventStatus.VOIDED);
    }

    function test_isSettleable() public {
        uint40 openTime = uint40(block.timestamp);

        vm.prank(keeper);
        bytes32 eventId = em.createEvent(bytes32("feed1"), openTime, openTime + 10, 2, bytes32(0));

        // Not settleable when OPEN
        assertFalse(settlement.isSettleable(eventId));

        // Lock
        vm.warp(openTime + 10);
        em.lockEvent(eventId);

        // Now settleable
        assertTrue(settlement.isSettleable(eventId));
    }
}
