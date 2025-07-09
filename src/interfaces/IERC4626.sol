//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IERC4626 {
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    event Fee_Updated(uint256 indexed oldFee, uint256 indexed newFee, address indexed owner);

    event Vault_Assets_Withdrawn(address indexed vault, address indexed owner, uint256 assets);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /*-----------------------OWNER ONLY FUNCTIONS--------------------*/

    function setFee(uint256 new_Fee) external;

    function withdrawVaultAssets() external returns (uint256 assets);

    /*------------------VIEW UNDERLYING ASSET DETAILS----------------*/

    function getUnderlyingAsset() external view returns (address);

    function getFee() external view returns (uint256);
}
