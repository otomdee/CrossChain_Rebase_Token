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

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RebaseToken
 * @author otomdee
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate that is the global interest rate at the time of deposit.
 */
contract RebaseToken is ERC20 {
    ///////////////////
    // Errors. ////////
    ///////////////////
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);
    ////////////////////
    // State Variables /
    ////////////////////

    uint256 PRECISION_FACTOR = 1e18;
    mapping(address => uint256) s_userInterestRate;
    mapping(address => uint256) s_userLastUpdatedTimeStamp; //last time tokens were minted to user

    uint256 private s_interestRate = 5e10; //0.000_000_005 per second
    ///////////////////
    // Events /////////
    ///////////////////

    event InterestRateSet(uint256 InterestRate);

    constructor() ERC20("Rebase Token", "RBT") {}

    function setInterestrate(uint256 _newInterestRate) external {
        uint256 currentInterestRate = s_interestRate;
        if (currentInterestRate < _newInterestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(currentInterestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    function mint(address _to, uint256 _amount) external {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    function balanceOf(address _user) public view override returns (uint256) {
        uint256 currentBalance = super.balanceOf(_user);
        uint256 interestEarned = currentBalance * _calculateUserAccumulatedInterest(_user);

        return (currentBalance + interestEarned);
    }

    function _calculateUserAccumulatedInterest(address _user) internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimeStamp[_user];

        uint256 accumulatedInterest = ((timeElapsed * s_userInterestRate[_user]) / PRECISION_FACTOR);

        return accumulatedInterest;
    }

    function _mintAccruedInterest(address user) internal {
        //get their current minted balance
        //get their current balance with interest
        //get the difference, which is their interest
    }

    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
