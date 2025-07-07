// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {IERC20} from "src/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "./interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";

import {Errors} from "./libraries/Errors.sol";

/* 

███████╗██████╗  ██████╗██╗  ██╗ ██████╗ ██████╗  ██████╗ 
██╔════╝██╔══██╗██╔════╝██║  ██║██╔════╝ ╚════██╗██╔════╝ 
█████╗  ██████╔╝██║     ███████║███████╗  █████╔╝███████╗ 
██╔══╝  ██╔══██╗██║     ╚════██║██╔═══██╗██╔═══╝ ██╔═══██╗
███████╗██║  ██║╚██████╗     ██║╚██████╔╝███████╗╚██████╔╝
╚══════╝╚═╝  ╚═╝ ╚═════╝     ╚═╝ ╚═════╝ ╚══════╝ ╚═════╝ 
                                                          
██╗   ██╗ █████╗ ██╗   ██╗██╗  ████████╗                  
██║   ██║██╔══██╗██║   ██║██║  ╚══██╔══╝                  
██║   ██║███████║██║   ██║██║     ██║                     
╚██╗ ██╔╝██╔══██║██║   ██║██║     ██║                     
 ╚████╔╝ ██║  ██║╚██████╔╝███████╗██║                     
  ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝                     
                                                                                                
 */

/**
 * @title ERC4626 Vault
 * @author [Your Name or Organization]
 * @notice ERC4626-compliant yield-bearing vault with basis point fee mechanism.
 * @dev This vault accepts an ERC20 asset, issues ERC20 shares, and charges configurable fees on deposits and withdrawals.
 *      Only the contract owner can set fees and withdraw accumulated protocol fees.
 */
contract ERC4626 is ERC20, IERC4626 {
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                                  STATE VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The owner of the vault. Has permission to change fee rate and withdraw vault's share holdings.
    address private immutable i_owner;

    /// @notice The current fee rate in basis points (1bp = 0.01%).
    uint256 private basis_point_fee = 100;

    /// @notice The maximum fee rate that can be charged (in basis points).
    uint256 private constant MAX_BASIS_POINT_FEE = 500;

    /// @notice The fee denominator to normalize basis point fee.
    uint256 private constant FEE_DENOMINATOR = 10_000;

    /// @notice The underlying asset accepted by the vault (ERC20 token).
    IERC20 private immutable asset;

    /// @notice Vault account data structure tracking total assets and shares.
    VaultAccount private vault_account;

    /*//////////////////////////////////////////////////////////////////////////
                                  DATA TYPES
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Struct to track total assets and total shares in the vault.
    struct VaultAccount {
        uint256 totalAssets;
        uint256 totalShares;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploys the ERC4626 vault.
     * @param _contractAddressOfAsset The contract address of the underlying ERC20 asset.
     * @param _name Name of the ERC20 token to be issued as shares.
     * @param _symbol Symbol of the ERC20 token to be issued as shares.
     * @dev The deployer becomes the owner of the vault.
     */
    constructor(
        address _contractAddressOfAsset,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        asset = IERC20(_contractAddressOfAsset);
        i_owner = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc IERC4626
     * @notice Deposit a specific amount of assets and receive corresponding shares.
     * @param assets Amount of underlying asset to deposit.
     * @param receiver Address to receive the minted shares.
     * @return shares Amount of shares minted to the receiver.
     */
    function deposit(
        uint256 assets,
        address receiver
    ) external override returns (uint256 shares) {
        validReceiver(receiver);

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

    /**
     * @inheritdoc IERC4626
     * @notice Mint a specific amount of shares by depositing the required assets.
     * @param shares Amount of shares to mint.
     * @param receiver Address to receive the minted shares.
     * @return assets Amount of assets deposited.
     */
    function mint(
        uint256 shares,
        address receiver
    ) external override returns (uint256 assets) {
        validReceiver(receiver);

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

    /**
     * @inheritdoc IERC4626
     * @notice Withdraw a specific amount of assets by burning the required shares.
     * @param assets Amount of underlying asset to withdraw.
     * @param receiver Address to receive the withdrawn assets.
     * @param owner Address whose shares will be burned.
     * @return shares Amount of shares burned.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external override returns (uint256 shares) {
        validReceiver(receiver);

        if ((shares = previewWithdraw(assets)) > balanceOf(owner)) {
            revert Errors.ERC4626__InsufficientShareBalance();
        }

        if (owner != msg.sender) {
            if (allowance(owner, msg.sender) < shares)
                revert Errors.ERC4626__NotApprovedToSpendShares();
        }

        vault_account.totalShares -= shares;
        _burn(owner, shares);

        vault_account.totalShares += withdrawFee(shares);
        _mint(address(this), withdrawFee(shares));

        vault_account.totalAssets -= assets;
        asset.transfer(receiver, assets);

        emit IERC4626.Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @inheritdoc IERC4626
     * @notice Redeem a specific amount of shares for the corresponding amount of assets.
     * @param shares Amount of shares to redeem.
     * @param receiver Address to receive the withdrawn assets.
     * @param owner Address whose shares will be burned.
     * @return assets Amount of assets withdrawn.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external override returns (uint256 assets) {
        validReceiver(receiver);

        if (shares > balanceOf(owner)) {
            revert Errors.ERC4626__InsufficientShareBalance();
        }
        if (owner != msg.sender) {
            if (allowance(owner, msg.sender) < shares)
                revert Errors.ERC4626__NotApprovedToSpendShares();
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

    /*//////////////////////////////////////////////////////////////////////////
                                OWNER ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Set a new fee rate (in basis points).
     * @dev Only callable by the vault owner.
     * @param new_Fee New fee rate in basis points (max: MAX_BASIS_POINT_FEE).
     */
    function setFee(uint256 new_Fee) external {
        onlyOwner();
        if (new_Fee > MAX_BASIS_POINT_FEE) revert Errors.ERC4626_FeeTooHigh();
        uint256 oldFee = basis_point_fee;
        basis_point_fee = new_Fee;
        emit Fee_Updated(oldFee, new_Fee, msg.sender);
    }

    /**
     * @notice Withdraw all protocol fee shares held by the vault to the owner.
     * @dev Only callable by the vault owner.
     * @return assets Amount of assets withdrawn.
     */
    function withdrawVaultAssets() external returns (uint256 assets) {
        onlyOwner();

        uint256 shares = balanceOf(address(this));
        assets = convertToAssets(shares);

        _burn(address(this), shares);
        vault_account.totalShares -= shares;

        asset.transfer(msg.sender, assets);
        vault_account.totalAssets -= assets;

        emit Vault_Assets_Withdrawn(address(this), msg.sender, assets);

        return assets;
    }

    /*//////////////////////////////////////////////////////////////////////////
                           VIEW UNDERLYING ASSET DETAILS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the address of the underlying ERC20 asset.
     * @return Address of the asset.
     */
    function getUnderlyingAsset() external view override returns (address) {
        return address(asset);
    }

    /**
     * @notice Returns the current fee rate in basis points.
     * @return Fee rate (basis points).
     */
    function getFee() external view override returns (uint256) {
        return basis_point_fee;
    }

    /*//////////////////////////////////////////////////////////////////////////
                           SIMULATE DEPOSITS/WITHDRAWALS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Simulate the number of shares minted for a given deposit of assets, after fees.
     * @param assets Amount of assets to deposit.
     * @return shares Amount of shares that would be minted.
     */
    function previewDeposit(
        uint256 assets
    ) public view returns (uint256 shares) {
        uint256 fee;
        shares = convertToShares(assets);
        fee = basis_point_fee.mulDivUp(shares, FEE_DENOMINATOR);
        return shares - fee;
    }

    /**
     * @notice Simulate the amount of assets required to mint a given number of shares, including fees.
     * @param shares Amount of shares to mint.
     * @return assets Amount of assets required.
     */
    function previewMint(uint256 shares) public view returns (uint256 assets) {
        uint256 fee;
        fee = basis_point_fee.mulDivUp(shares, FEE_DENOMINATOR);
        assets = convertToAssets(shares + fee);
        return assets;
    }

    /**
     * @notice Simulate the number of shares required to withdraw a given amount of assets, including fees.
     * @param assets Amount of assets to withdraw.
     * @return shares Amount of shares required.
     */
    function previewWithdraw(
        uint256 assets
    ) public view returns (uint256 shares) {
        uint256 fee;
        shares = convertToShares(assets);
        fee = basis_point_fee.mulDivUp(shares, FEE_DENOMINATOR);
        shares += fee;
        return shares;
    }

    /**
     * @notice Simulate the amount of assets received by redeeming a given number of shares, after fees.
     * @param shares Amount of shares to redeem.
     * @return assets Amount of assets received.
     */
    function previewRedeem(
        uint256 shares
    ) public view returns (uint256 assets) {
        uint256 fee;
        fee = basis_point_fee.mulDivUp(shares, FEE_DENOMINATOR);
        shares -= fee;
        assets = convertToAssets(shares);
        return assets;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                VIEW VAULT DETAILS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets held by the vault.
     * @return Total assets.
     */
    function totalAssets() public view returns (uint256) {
        return vault_account.totalAssets;
    }

    /**
     * @notice Returns the total number of shares issued by the vault.
     * @return Total shares.
     */
    function totalShares() public view returns (uint256) {
        return vault_account.totalShares;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            DEPOSIT/WITHDRAWAL LIMITS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the maximum amount of assets that can be deposited.
     * @dev Unlimited by default.
     * @return Maximum deposit amount.
     */
    function maxDeposit() public pure returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Returns the maximum amount of shares that can be minted.
     * @dev Unlimited by default.
     * @return Maximum mint amount.
     */
    function maxMint() public pure returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Returns the maximum amount of assets that can be withdrawn by the caller.
     * @return Maximum withdrawable assets.
     */
    function maxWithdraw() public view returns (uint256) {
        return previewRedeem(balanceOf(msg.sender));
    }

    /**
     * @notice Returns the maximum amount of shares that can be redeemed by the caller.
     * @return Maximum redeemable shares.
     */
    function maxRedeem() public view returns (uint256) {
        return balanceOf(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////////////////
                    CONVERSION FROM ASSETS TO SHARES AND VICE VERSA
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Converts a given amount of assets to shares, based on current vault ratios.
     * @param assets Amount of assets to convert.
     * @return shares Equivalent shares.
     */
    function convertToShares(
        uint256 assets
    ) internal view returns (uint256 shares) {
        return
            totalShares() == 0
                ? assets / 5
                : totalShares().mulDivDown(assets, totalAssets());
    }

    /**
     * @dev Converts a given amount of shares to assets, based on current vault ratios.
     * @param shares Amount of shares to convert.
     * @return assets Equivalent assets.
     */
    function convertToAssets(
        uint256 shares
    ) internal view returns (uint256 assets) {
        return totalAssets().mulDivDown(shares, totalShares());
    }

    /*//////////////////////////////////////////////////////////////////////////
                                FEE CALCULATION
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Calculates the protocol fee (in shares) for a given asset deposit.
     * @param assets Amount of assets being deposited.
     * @return Fee in shares.
     */
    function depositFee(uint256 assets) internal view returns (uint256) {
        return
            basis_point_fee.mulDivUp(convertToShares(assets), FEE_DENOMINATOR);
    }

    /**
     * @dev Calculates the protocol fee (in shares) for a given withdrawal.
     * @param shares Amount of shares being withdrawn.
     * @return Fee in shares.
     */
    function withdrawFee(uint256 shares) internal view returns (uint256) {
        return basis_point_fee.mulDivUp(shares, FEE_DENOMINATOR);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            ACCESS CONTROL, RECEIVER VALIDATION
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Reverts if the caller is not the contract owner.
     *      Used for access control on owner-only functions.
     */
    function onlyOwner() internal view {
        require(msg.sender == i_owner, Errors.ERC4626_OnlyOwnerCanSetFees());
    }

    /**
     * @dev Validates that the receiver is not the zero address or the vault itself.
     *      Used to prevent misdirected transfers.
     * @param receiver Address to validate.
     */
    function validReceiver(address receiver) internal view {
        require(
            !((receiver == address(0)) || (receiver == address(this))),
            Errors.ERC4626__InvalidReceiver()
        );
    }
}
