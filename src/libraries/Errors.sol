//SPDX-License-Identifier:MIT
pragma solidity 0.8.30;

library Errors {
    error ERC4626__InsufficientAssets();
    error ERC4626__InsufficientShareBalance();
    error ERC4626_OnlyOwnerCanSetFees();
    error ERC4626_FeeTooHigh();
    error ERC4626__InvalidReceiver();
    error ERC4626__NotApprovedToSpendShares();
}
