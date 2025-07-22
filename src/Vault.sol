// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

pragma solidity ^0.8.24;

contract Vault {
    error VAULT__RedeemFailed();

    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    //pass RBT token to vault in constructor
    //deposit function that mints RBT token to caller
    //redeem function

    constructor(address _rebaseTokenAdress) {
        i_rebaseToken = IRebaseToken(_rebaseTokenAdress);
    }

    receive() external payable {}

    function deposit() external payable {
        //get current global interest rate of token
        uint256 interestRate = i_rebaseToken.getInterestRate();
        // Mint RBT tokens to the caller
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);

        emit Deposit(msg.sender, msg.value);
    }

    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }

        i_rebaseToken.burn(msg.sender, _amount); //should revert if amount is more than balance

        //transfer eth to the caller
        (bool sucess,) = payable(msg.sender).call{value: _amount}("");
        if (!sucess) {
            revert VAULT__RedeemFailed();
        }
    }

    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
