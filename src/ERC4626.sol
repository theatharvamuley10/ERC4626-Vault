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
// view & pure functions

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "src/interfaces/IERC20.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {Errors} from "./libraries/Errors.sol";
import {IERC4626} from "./interfaces/IERC4626.sol";

contract ERC4626 is ERC20, IERC4626 {
    /*------------------------Library Setup---------------------------*/

    using FixedPointMathLib for uint256;

    /*-------------------------Immutables-----------------------------*/

    address contractAddressOfAsset;
    IERC20 private immutable asset; // underlying asset
    address private immutable i_owner;
    uint256 private basis_point_fee = 100;
    uint256 private constant FEE_DENOMINATOR = 10_000;
    uint256 private constant MAX_BASIS_POINT_FEE = 500;
    VaultAccount private vault_account;

    struct VaultAccount {
        uint256 totalAssets;
        uint256 totalShares;
    }

    /*-------------------------CONSTRUCTOR---------------------------*/

    constructor(
        address _contractAddressOfAsset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {
        contractAddressOfAsset = _contractAddressOfAsset;
        asset = IERC20(_contractAddressOfAsset);
        i_owner = msg.sender;
    }

    /*---------------------------MODIFIERS---------------------------*/

    modifier onlyOwner() {
        if (msg.sender != i_owner) revert Errors.ERC4626_OnlyOwnerCanSetFees();
        _;
    }

    modifier validReceiver(address receiver) {
        if ((receiver == address(0)) || (receiver == address(this)))
            revert Errors.ERC4626__InvalidReceiver();
        _;
    }

    /*--------------------DEPOSIT/WITHDRAWAL LOGIC-------------------*/

    function deposit(
        uint256 assets,
        address receiver
    ) external override validReceiver(receiver) returns (uint256 shares) {
        if ((shares = previewDeposit(assets)) == 0) {
            revert Errors.ERC4626__InsufficientAssets();
        }

        asset.transferFrom(msg.sender, address(this), assets);
        vault_account.totalAssets += assets;

        _mint(receiver, shares);
        vault_account.totalShares += shares;

        _mint(address(this), depositFee(assets));
        vault_account.totalShares += depositFee(assets);

        emit IERC4626.Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(
        uint256 shares,
        address receiver
    ) external override validReceiver(receiver) returns (uint256 assets) {
        if (asset.balanceOf(msg.sender) < (assets = previewMint(shares))) {
            revert Errors.ERC4626__InsufficientAssets();
        }

        asset.transferFrom(msg.sender, address(this), assets);
        vault_account.totalAssets += assets;

        _mint(receiver, shares);
        vault_account.totalShares += shares;

        _mint(address(this), convertToShares(assets) - shares);
        vault_account.totalShares += depositFee(assets);

        emit IERC4626.Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external override validReceiver(receiver) returns (uint256 shares) {
        if ((shares = previewWithdraw(assets)) > balanceOf[owner]) {
            revert Errors.ERC4626__InsufficientShareBalance();
        }

        if (owner != msg.sender) {
            if (allowance[owner][msg.sender] != type(uint256).max)
                allowance[owner][msg.sender] -= shares;
        }

        vault_account.totalShares -= shares;
        _burn(owner, shares);

        vault_account.totalShares += withdrawFee(shares);
        _mint(address(this), withdrawFee(shares));

        vault_account.totalAssets -= assets;
        asset.transfer(receiver, assets);

        emit IERC4626.Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external override validReceiver(receiver) returns (uint256 assets) {
        if (shares > balanceOf[owner]) {
            revert Errors.ERC4626__InsufficientShareBalance();
        }
        if (owner != msg.sender) {
            if (allowance[owner][msg.sender] != type(uint256).max)
                allowance[owner][msg.sender] -= shares;
        }
        assets = previewRedeem(shares);

        vault_account.totalShares -= shares;
        _burn(owner, shares);

        vault_account.totalShares += withdrawFee(shares);
        _mint(address(this), withdrawFee(shares));

        vault_account.totalAssets -= assets;
        asset.transfer(receiver, assets);

        emit IERC4626.Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /*-----------------------OWNER ONLY FUNCTIONS--------------------*/

    function setFee(uint256 new_Fee) external override onlyOwner {
        if (new_Fee > MAX_BASIS_POINT_FEE) revert Errors.ERC4626_FeeTooHigh();
        uint256 oldFee = basis_point_fee;
        basis_point_fee = new_Fee;
        emit Fee_Updated(oldFee, new_Fee, msg.sender);
    }

    function withdrawVaultAssets()
        external
        override
        onlyOwner
        returns (uint256 assets)
    {
        uint256 shares = balanceOf[address(this)];
        assets = convertToAssets(shares);

        _burn(address(this), shares);
        vault_account.totalShares -= shares;

        asset.transfer(msg.sender, assets);
        vault_account.totalAssets -= assets;

        emit Vault_Assets_Withdrawn(address(this), msg.sender, assets);

        return assets;
    }

    /*------------------VIEW UNDERLYING ASSET DETAILS----------------*/

    function getUnderlyingAsset() external view override returns (address) {
        return contractAddressOfAsset;
    }

    function getFee() external view override returns (uint256) {
        return basis_point_fee;
    }

    /*-----------------SIMULATE DEPOSITS/WITHDRAWALS-----------------*/

    function previewDeposit(
        uint256 assets
    ) public view returns (uint256 shares) {
        uint256 fee;
        shares = convertToShares(assets);
        fee = basis_point_fee.mulDivUp(shares, FEE_DENOMINATOR);
        return shares - fee;
    }

    function previewMint(uint256 shares) public view returns (uint256 assets) {
        uint256 fee;
        fee = basis_point_fee.mulDivUp(shares, FEE_DENOMINATOR);
        assets = convertToAssets(shares + fee);
        return assets;
    }

    function previewWithdraw(
        uint256 assets
    ) public view returns (uint256 shares) {
        uint256 fee;
        shares = convertToShares(assets);
        fee = basis_point_fee.mulDivUp(shares, FEE_DENOMINATOR);
        shares += fee;
        return shares;
    }

    function previewRedeem(
        uint256 shares
    ) public view returns (uint256 assets) {
        uint256 fee;
        fee = basis_point_fee.mulDivUp(shares, FEE_DENOMINATOR);
        shares -= fee;
        assets = convertToAssets(shares);
        return assets;
    }

    /*------------------------VIEW VAULT DETAILS---------------------*/

    function totalAssets() public view returns (uint256) {
        return vault_account.totalAssets;
    }

    function totalShares() public view returns (uint256) {
        return vault_account.totalShares;
    }

    /*------------------DEPOSIT/WITHDRAWAL LIMITS--------------------*/

    function maxDeposit() public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint() public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw() public view returns (uint256) {
        return previewRedeem(balanceOf[msg.sender]);
    }

    function maxRedeem() public view returns (uint256) {
        return balanceOf[msg.sender];
    }

    /*-------CONVERSION FROM ASSETS TO SHARES AND VICE VERSA---------*/

    function convertToShares(
        uint256 assets
    ) internal view returns (uint256 shares) {
        return
            totalShares() == 0
                ? assets / 5
                : totalShares().mulDivDown(assets, totalAssets());
    }

    function convertToAssets(
        uint256 shares
    ) internal view returns (uint256 assets) {
        return totalAssets().mulDivDown(shares, totalShares());
    }

    /*------------------------FEE CALCULATION------------------------*/

    function depositFee(uint256 assets) internal view returns (uint256) {
        return
            basis_point_fee.mulDivUp(convertToShares(assets), FEE_DENOMINATOR);
    }

    function withdrawFee(uint256 shares) internal view returns (uint256) {
        return basis_point_fee.mulDivUp(shares, FEE_DENOMINATOR);
    }
}
