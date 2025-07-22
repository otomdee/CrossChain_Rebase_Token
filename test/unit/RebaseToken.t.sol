// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {RebaseToken} from "../../src/RebaseToken.sol";
import {Vault} from "../../src/Vault.sol";
import {Test, console} from "forge-std/Test.sol";

contract RebaseTokenTest is Test {
    RebaseToken public rebaseToken;
    Vault public vault;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    uint256 public USER_BALANCE = 10 ether;

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(address(rebaseToken));
        // Grant mint and burn role to the vault
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.deal(owner, USER_BALANCE);
        payable(address(vault)).call{value: USER_BALANCE}("");
        vm.stopPrank();
    }

    function testInterestRateIsLinear(uint256 amount) public {
        amount = bound(amount, 1e8, type(uint96).max);

        vm.deal(user1, amount);

        vm.startPrank(user1);
        vault.deposit{value: amount}();
        uint256 startingBalance = rebaseToken.balanceOf(user1);
        console.log("starting balance: ", startingBalance);
        assertEq(startingBalance, amount);
        vm.warp(block.timestamp + 1 hours);

        uint256 middleBalance = rebaseToken.balanceOf(user1);
        assert(middleBalance > startingBalance);

        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user1);
        assert(endBalance > middleBalance);

        assertApproxEqAbs((endBalance - middleBalance), (middleBalance - startingBalance), 1);
        vm.stopPrank();
    }

    function testRedeemImmediately(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.deal(user1, amount);

        vm.startPrank(user1);
        vault.deposit{value: amount}();
        uint256 startingBalance = rebaseToken.balanceOf(user1);
        assertEq(startingBalance, amount);

        vault.redeem(type(uint256).max);
        uint256 endingBalance = rebaseToken.balanceOf(user1);
        assertEq(endingBalance, 0);
        assertEq(user1.balance, amount);
        vm.stopPrank();
    }

    function testCanRedeemAfterSomeTimeHasPassed(uint256 amount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max);
        amount = bound(amount, 1e5, type(uint96).max);

        vm.deal(user1, amount);
        vm.prank(user1);
        vault.deposit{value: amount}();

        uint256 startingBalance = rebaseToken.balanceOf(user1);
        assertEq(startingBalance, amount);

        vm.warp(block.timestamp + time);

        uint256 updatedBalance = rebaseToken.balanceOf(user1);

        vm.deal(owner, updatedBalance - startingBalance);
        vm.prank(owner);
        addRewardsToVault(updatedBalance - startingBalance);

        vm.prank(user1);
        vault.redeem(type(uint256).max);

        uint256 endingBalance = rebaseToken.balanceOf(user1);
        assertEq(endingBalance, 0); //after redeem, user has 0 rebase tokens
        assertEq(updatedBalance, user1.balance); //entire RBT is exchanged directly for ETH
        assert(user1.balance > startingBalance); //user gained some ETH by redeeming accrued RBT for ETH after some time
    }

    function testCanTransferTokensAndInheritInterestRate(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5); //amount to send will always be > amount in tests

        vm.deal(user1, amount);

        vm.prank(user1);
        vault.deposit{value: amount}();

        uint256 user1balanceBefore = rebaseToken.balanceOf(user1);
        uint256 user2balanceBefore = rebaseToken.balanceOf(user2);

        vm.prank(user1);
        rebaseToken.transfer(user2, amountToSend);

        uint256 user1balanceAfter = rebaseToken.balanceOf(user1);
        uint256 user2balanceAfter = rebaseToken.balanceOf(user2);

        assert(user1balanceAfter == user1balanceBefore - amountToSend);
        assert(user2balanceAfter == user2balanceBefore + amountToSend);

        //check rate
        uint256 user2Rate = rebaseToken.getUserInterestRate(user2);
        uint256 user1Rate = rebaseToken.getUserInterestRate(user1);
        assertEq(user1Rate, user2Rate);
    }

    function testCannotCallMintAndBurnIfNotOwner() public {
        vm.expectRevert();
        vm.prank(user1);
        rebaseToken.mint(user1, USER_BALANCE, rebaseToken.getCurrentInterestRate());
    }

    function testPrincipleBalanceOfReturnsExpectedAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.deal(user1, amount);

        vm.prank(user1);
        vault.deposit{value: amount}();

        assertEq(rebaseToken.principalBalanceOf(user1), amount);

        vm.warp(block.timestamp + 1 hours);

        assertEq(rebaseToken.principalBalanceOf(user1), amount);
    }

    function testGetInterestRate(uint256 rate) public {
        uint256 startingInterestRate = 5e10;

        rate = bound(rate, 1e5, startingInterestRate); //rate can only decrease

        assertEq(rebaseToken.getCurrentInterestRate(), startingInterestRate);

        vm.prank(owner);
        rebaseToken.setInterestRate(rate);

        assertEq(rebaseToken.getCurrentInterestRate(), rate);
    }

    //helper
    function addRewardsToVault(uint256 rewardAmount) public {
        payable(address(vault)).call{value: rewardAmount}("");
    }
}
