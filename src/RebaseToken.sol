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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author otomdee
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate that is the global interest rate at the time of deposit.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
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
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    ///////////////////
    // Events /////////
    ///////////////////

    event InterestRateSet(uint256 InterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    function setInterestRate(uint256 _newInterestRate) external {
        uint256 currentInterestRate = s_interestRate;
        if (currentInterestRate < _newInterestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(currentInterestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }

        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    function balanceOf(address _user) public view override returns (uint256) {
        uint256 currentBalance = super.balanceOf(_user);
        uint256 interestEarned = currentBalance * _calculateUserAccumulatedInterest(_user);

        return (currentBalance + interestEarned);
    }

    /**
     * @notice Transfers tokens from the caller to a recipient.
     * Accrued interest for both sender and recipient is minted before the transfer.
     * If the recipient is new, they inherit the sender's interest rate.
     * @param _recipient The address to transfer tokens to.
     * @param _amount The amount of tokens to transfer. Can be type(uint256).max to transfer full balance.
     * @return A boolean indicating whether the operation succeeded.
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        // 1. Mint accrued interest for both sender and recipient
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);

        // 2. Handle request to transfer maximum balance
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender); // Use the interest-inclusive balance
        }

        // 3. Set recipient's interest rate if they are new (balance is checked *before* super.transfer)
        // We use balanceOf here to check the effective balance including any just-minted interest.
        // If _mintAccruedInterest made their balance non-zero, but they had 0 principle, this still means they are "new" for rate setting.
        // A more robust check for "newness" for rate setting might be super.balanceOf(_recipient) == 0 before any interest minting for the recipient.
        // However, the current logic is: if their *effective* balance is 0 before the main transfer part, they get the sender's rate.
        if (balanceOf(_recipient) == 0 && _amount > 0) {
            // Ensure _amount > 0 to avoid setting rate on 0-value initial transfer
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }

        // 4. Execute the base ERC20 transfer
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfers tokens from one address to another, on behalf of the sender,
     * provided an allowance is in place.
     * Accrued interest for both sender and recipient is minted before the transfer.
     * If the recipient is new, they inherit the sender's interest rate.
     * @param _sender The address to transfer tokens from.
     * @param _recipient The address to transfer tokens to.
     * @param _amount The amount of tokens to transfer. Can be type(uint256).max to transfer full balance.
     * @return A boolean indicating whether the operation succeeded.
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);

        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender); // Use the interest-inclusive balance of the _sender
        }

        // Set recipient's interest rate if they are new
        if (balanceOf(_recipient) == 0 && _amount > 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }

        return super.transferFrom(_sender, _recipient, _amount);
    }

    function _calculateUserAccumulatedInterest(address _user) internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimeStamp[_user];

        uint256 accumulatedInterest = ((timeElapsed * s_userInterestRate[_user]) / PRECISION_FACTOR);

        return accumulatedInterest;
    }

    function _mintAccruedInterest(address _user) internal {
        //get their current minted balance
        //get their current balance with interest
        //get the difference, which is their interest
        uint256 currentBalance = super.balanceOf(_user);
        uint256 balanceWithInterest = balanceOf(_user);

        s_userLastUpdatedTimeStamp[_user] = block.timestamp;
        _mint(_user, (balanceWithInterest - currentBalance));
    }

    /**
     * @notice Returns the principle balance of a user, which is the minted balance without accrued interest.
     * @param _user The address of the user.
     * @return The principle balance of the user.
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice Returns the current global interest rate.
     * @return The current interest rate in the contract.
     */
    function getCurrentInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}
