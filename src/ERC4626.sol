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

import {ERC20} from "@solmate/src/tokens/ERC20.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";

contract ERC4626 is ERC20 {
    using FixedPointMathLib for uint256;
    /*-------------------------Immutables----------------------------*/

    ERC20 private immutable asset; // underlying asset
    address private immutable i_owner;
    uint256 private basis_point_fee = 200;
    uint256 private constant FEE_DENOMINATOR = 10_000;
    uint256 private constant MAX_BASIS_POINT_FEE = 500;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {
        asset = _asset;
        i_owner = msg.sender;
    }

    /*----------------------------EVENTS-----------------------------*/

    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Fee_Updated(
        uint256 indexed oldFee,
        uint256 indexed newFee,
        address indexed owner
    );

    event Vault_Assets_Withdrawn(
        address indexed vault,
        address indexed owner,
        uint256 assets
    );

    /*---------------------------MODIFIERS---------------------------*/

    modifier onlyOwner() {
        require(msg.sender == i_owner, "ONLY OWNER CAN PERFORM THIS ACTION");
        _;
    }

    /*--------------------DEPOSIT/WITHDRAWAL LOGIC-------------------*/

    function deposit(
        uint256 assets,
        address receiver
    ) public returns (uint256 shares) {
        require(
            (shares = previewDeposit(assets)) != 0,
            "ZERO SHARES WILL BE RECEIVED"
        );

        asset.transferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);
        _mint(address(this), convertToShares(assets) - shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public returns (uint256 assets) {
        require(
            asset.balanceOf(msg.sender) >= (assets = previewMint(shares)),
            "INSUFFICIENT ASSETS"
        );

        asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        _mint(address(this), convertToShares(assets) - shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public returns (uint256 shares) {
        require(
            (shares = previewWithdraw(assets)) <= balanceOf[owner],
            "INSUFFICIENT BALANCE OF SHARES"
        );

        if (owner != msg.sender) {
            if (allowance[owner][msg.sender] != type(uint256).max)
                allowance[owner][msg.sender] -= shares;
        }

        _burn(owner, shares);
        _mint(address(this), shares - convertToShares(assets));
        asset.transfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public returns (uint256 assets) {
        require(shares <= balanceOf[owner], "INSUFFICIENT BALANCE OF SHARES");
        if (owner != msg.sender) {
            if (allowance[owner][msg.sender] != type(uint256).max)
                allowance[owner][msg.sender] -= shares;
        }
        assets = previewRedeem(shares);

        _burn(owner, shares);
        _mint(address(this), shares - convertToShares(assets));
        asset.transfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /*-------CONVERSION FROM ASSETS TO SHARES AND VICE VERSA---------*/

    // total asset supply in vault = asset.balance[address(this)]
    // total shares supply in vault = balanceOf[address(this)]

    function convertToShares(
        uint256 assets
    ) public view returns (uint256 shares) {
        uint256 supply = totalSupply;
        return
            supply == 0
                ? assets
                : totalSupply.mulDivDown(assets, totalAssets());
    }

    function convertToAssets(
        uint256 shares
    ) public view returns (uint256 assets) {
        return totalAssets().mulDivDown(shares, totalSupply);
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

    /*------------------DEPOSIT/WITHDRAWAL LIMITS--------------------*/

    function maxDeposit() public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint() public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        return convertToAssets(balanceOf[owner]);
    }

    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf[owner];
    }

    /*------------------VIEW UNDERLYING ASSET DETAILS----------------*/

    function getAsset() public view returns (address) {
        address assetTokenAddress = address(ERC20(asset));
        return assetTokenAddress;
    }

    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /*-----------------------OWNER ONLY FUNCTIONS--------------------*/

    function setFee(uint256 new_Fee) external onlyOwner {
        require(new_Fee <= MAX_BASIS_POINT_FEE, "FEE TOO HIGH");
        uint256 oldFee = basis_point_fee;
        basis_point_fee = new_Fee;
        emit Fee_Updated(oldFee, new_Fee, msg.sender);
    }

    function withdrawVaultAssets() external onlyOwner returns (uint256 assets) {
        uint256 shares = balanceOf[address(this)];
        assets = convertToAssets(shares);

        _burn(address(this), shares);
        asset.transfer(msg.sender, assets);

        emit Vault_Assets_Withdrawn(address(this), msg.sender, assets);

        return assets;
    }

    /** Positives:
✅ Fixed critical fee math - Proper basis point scaling (200 = 2%) with FEE_DENOMINATOR
✅ Safer math operations - Using FixedPointMathLib prevents rounding errors
✅ Fee withdrawal mechanism - WithdrawVaultAssets() lets owner claim accumulated fees
✅ Fee cap - MAX_BASIS_POINT_FEE prevents excessive fees (max 5%)
✅ Consistent asset handling - Fixed mint() to transfer assets to vault, not receiver

    Areas for Improvement:
⚠️ No reentrancy protection - External calls before state changes (asset.transfer)
⚠️ No zero-address checks - In functions like deposit(receiver)
⚠️ Unbounded loops risk - If asset has callback hooks (not common but possible)
*/
}
