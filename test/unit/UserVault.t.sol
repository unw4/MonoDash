// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {UserVault} from "../../src/core/UserVault.sol";

contract UserVaultTest is Test {
    UserVault public vault;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public engine = makeAddr("engine");

    function setUp() public {
        vault = new UserVault();
        vault.setAuthorizedEngine(engine, true);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    // ===================== DEPOSIT =====================

    function test_deposit_success() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        (uint256 available, uint256 locked) = vault.getBalance(alice);
        assertEq(available, 1 ether);
        assertEq(locked, 0);
    }

    function test_deposit_reverts_zero() public {
        vm.prank(alice);
        vm.expectRevert("UserVault: zero deposit");
        vault.deposit{value: 0}();
    }

    function test_deposit_multiple() public {
        vm.startPrank(alice);
        vault.deposit{value: 1 ether}();
        vault.deposit{value: 2 ether}();
        vm.stopPrank();

        (uint256 available,) = vault.getBalance(alice);
        assertEq(available, 3 ether);
    }

    // ===================== WITHDRAW =====================

    function test_withdraw_success() public {
        vm.prank(alice);
        vault.deposit{value: 5 ether}();

        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        vault.withdraw(3 ether);

        assertEq(alice.balance, balanceBefore + 3 ether);
        (uint256 available,) = vault.getBalance(alice);
        assertEq(available, 2 ether);
    }

    function test_withdraw_reverts_insufficient() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        vm.prank(alice);
        vm.expectRevert("UserVault: insufficient balance");
        vault.withdraw(2 ether);
    }

    // ===================== LOCK/UNLOCK =====================

    function test_lockBalance_success() public {
        vm.prank(alice);
        vault.deposit{value: 5 ether}();

        vm.prank(engine);
        vault.lockBalance(alice, 2 ether);

        (uint256 available, uint256 locked) = vault.getBalance(alice);
        assertEq(available, 3 ether);
        assertEq(locked, 2 ether);
    }

    function test_lockBalance_reverts_unauthorized() public {
        vm.prank(alice);
        vault.deposit{value: 5 ether}();

        vm.prank(alice);
        vm.expectRevert("UserVault: not authorized");
        vault.lockBalance(alice, 1 ether);
    }

    function test_lockBalance_reverts_insufficient() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();

        vm.prank(engine);
        vm.expectRevert("UserVault: insufficient available");
        vault.lockBalance(alice, 2 ether);
    }

    function test_unlockBalance_success() public {
        vm.prank(alice);
        vault.deposit{value: 5 ether}();

        vm.prank(engine);
        vault.lockBalance(alice, 3 ether);

        vm.prank(engine);
        vault.unlockBalance(alice, 2 ether);

        (uint256 available, uint256 locked) = vault.getBalance(alice);
        assertEq(available, 4 ether);
        assertEq(locked, 1 ether);
    }

    // ===================== CREDIT/DEDUCT =====================

    function test_creditWinnings() public {
        vm.prank(engine);
        vault.creditWinnings(alice, 5 ether);

        (uint256 available,) = vault.getBalance(alice);
        assertEq(available, 5 ether);
    }

    function test_deductLocked() public {
        vm.prank(alice);
        vault.deposit{value: 5 ether}();

        vm.prank(engine);
        vault.lockBalance(alice, 3 ether);

        vm.prank(engine);
        vault.deductLocked(alice, 2 ether);

        (uint256 available, uint256 locked) = vault.getBalance(alice);
        assertEq(available, 2 ether);
        assertEq(locked, 1 ether);
    }

    // ===================== PARALLEL ISOLATION =====================

    function test_parallel_isolation_deposits() public {
        vm.prank(alice);
        vault.deposit{value: 10 ether}();

        vm.prank(bob);
        vault.deposit{value: 20 ether}();

        (uint256 aliceAvail,) = vault.getBalance(alice);
        (uint256 bobAvail,) = vault.getBalance(bob);

        assertEq(aliceAvail, 10 ether);
        assertEq(bobAvail, 20 ether);
    }

    // ===================== FUZZ =====================

    function testFuzz_deposit_withdraw(uint96 amount) public {
        vm.assume(amount > 0);
        vm.deal(alice, uint256(amount));

        vm.prank(alice);
        vault.deposit{value: amount}();

        vm.prank(alice);
        vault.withdraw(amount);

        (uint256 available,) = vault.getBalance(alice);
        assertEq(available, 0);
    }
}
