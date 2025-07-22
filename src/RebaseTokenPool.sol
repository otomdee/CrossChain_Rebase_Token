// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol"; // For CCIP structs

contract RebaseTokenPool is TokenPool {
    constructor(IERC20 _token, address[] memory _allowlist, address _rnmProxy, address _router)
        TokenPool(_token, _allowlist, _rnmProxy, _router)
    {}

    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        override
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        _validateLockOrBurn(lockOrBurnIn);

        //get address of sender
        address originalSender = lockOrBurnIn.originalSender;

        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(originalSender); //i_token from tokenPool constructor

        //burn tokens
        //tokens are transferred to the pool first, then lockorBurn is called, so burn() takes the pool address, not that of the sender
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate) // Encode the interest rate to send cross-chain
        });
    }

    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn);

        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256)); //decode user interest rate from releaseOrMintIn

        address receiver = releaseOrMintIn.receiver;

        //mint RBT to reciever
        IRebaseToken(address(i_token)).mint(
            receiver,
            releaseOrMintIn.amount,
            userInterestRate // Pass the interest rate to the rebase token's mint function
        );

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
    }
}
