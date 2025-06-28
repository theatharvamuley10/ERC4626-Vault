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

contract ERC4626 is ERC20 {
    /*-------------------------Immutables----------------------------*/

    ERC20 private immutable asset; // underlying asset
    address private immutable owner;
    uint256 private baseFee = 0.02;

    constructor(
        ERC20 _asset,
        string _name,
        string _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {
        asset = _asset;
        owner = msg.sender;
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
    )

    event Fee_Updated(
        uint256 indexed oldFee,
        uint256 indexed newFee,
        uint256 indexed owner
    )

    /*---------------------------MODIFIERS---------------------------*/

    modifier onlyOwner {
        require(msg.sender == owner, "ONLY OWNER CAN PERFORM THIS ACTION");
    }

    /*--------------------DEPOSIT/WITHDRAWAL LOGIC-------------------*/

    function deposit(
        uint256 assets,
        address receiver
    ) public nonpayable returns (uint256 shares) {
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
    ) public nonpayable returns (uint256 assets) {
        require(
            asset.balanceOf[msg.sender] >= (assets = previewMint(shares)),
            "INSUFFICIENT ASSETS"
        );

        asset.transferFrom(msg.sender, receiver, assets);
        _mint(receiver, shares);
        _mint(address(this), convertToShares(assets)-shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public nonpayable returns (uint256 shares) {
        require(
            (shares = previewWithdraw(assets)) <= balanceOf[owner],
            "INSUFFICIENT BALANCE OF SHARES"
        );

        if (owner != msg.sender){
            if(allowance[owner][msg.sender] != type(uint256).max) allowance[owner][msg.sender] -= shares;
        }

        _burn(owner, shares);
        _mint(address(this, shares - convertToShares(assets)));
        asset.transfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public nonpayable returns (uint256 assets) {
        require(shares <= balanceOf[owner],"INSUFFICIENT BALANCE OF SHARES");
        if (owner != msg.sender){
            if(allowance[owner][msg.sender] != type(uint256).max) allowance[owner][msg.sender] -= shares;
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

    function totalAssets() public view returns (uint256 totalAssets){
        return asset.balanceOf[address(this)];
    }

    function convertToShares(
        uint256 assets
    ) public view returns (uint256 shares) {
        shares = totalSupply * asset / totalAssets;
        return shares;
    }

    function convertToAssets(
        uint256 shares
    ) public view returns (uint256 assets) {
        assets = total assets * shares / totalSupply;
        return assets;
    }

    /*-----------------SIMULATE DEPOSITS/WITHDRAWALS-----------------*/

    function previewDeposit(uint256 assets) public view returns (uint256 shares){
        shares = convertToShares(assets);
        fee = baseFee*shares;
        return shares - fee;
    }

    function previewMint(uint256 shares) public view returns (uint256 assets){
        fee = baseFee * shares;
        assets = convertToAssets(shares+fee);
        return assets;
    }

    function previewWithdraw(uint256 assets) public view returns (uint256 shares){
        shares = convertToShares(assets);
        fee = baseFee * shares;
        shares += fee;
        return shares;
    }

    function previewRedeem(uint256 shares) public view returns (uint256 assets){
        fee = baseFee * shares;
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
        return asset.balanceOf[address(this)];
    }

    /*-----------------------OWNER ONLY FUNCTIONS--------------------*/

    function setFee(uint256 newFee) external onlyOwner{
        baseFee = newFee;
        emit (oldFee, newFee, owner);
    }
}
