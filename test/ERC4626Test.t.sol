// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ERC4626} from "src/ERC4626.sol";
import {ERC20} from "src/mocks/MockERC20.sol";
import {DeployVault} from "script/DeployERC4626.s.sol";
import {stdError} from "forge-std/StdError.sol";
import {Errors} from "../src/libraries/Errors.sol";

contract TestVault is Test {
    /*-------------------------STATE VARIABLES------------------------*/

    ERC20 mockERC20;
    ERC4626 vault;

    address payable alice = payable(makeAddr("alice"));
    address payable bob = payable(makeAddr("bob"));
    address private immutable owner = msg.sender;

    uint256 INITIAL_VAULT_ASSETS = 10_000;

    uint256 private constant ALICE_INITIAL_TOKENS = 50_000;
    uint256 private constant ALICE_DEPOSIT = 30_000;
    uint256 private constant ALICE_LIMITED_APPROVAL = 20_000;
    address private constant INVALID_RECEIVER = address(0);

    function setUp() public {
        //Instantiating mockERC20 Token with owner owning 100_000 tokens
        mockERC20 = new ERC20("MocKERCToken", "MT", 6, owner);

        // Deploy Vault with mockERC20 as underlying asset
        DeployVault deployer = new DeployVault();
        vault = deployer.run(address(mockERC20));

        // Owner does the following two things
        vm.startPrank(owner);

        // 1. Provides initial seed to vault with 10_000 asset tokens
        mockERC20.approve(address(vault), INITIAL_VAULT_ASSETS);
        vault.deposit(INITIAL_VAULT_ASSETS, owner);

        // 2. Transfer Alice 50_000 asset tokens for further testing
        mockERC20.transfer(alice, ALICE_INITIAL_TOKENS);
        vm.stopPrank();
    }

    /**
     * AFTER EACH SETUP
     * Vault has 10_000 deposited assets, 2000 total shares supply
     * Alice has 50_000 asset tokens, 0 shares
     * Bob has 0 asset tokens, 0 shares
     * Owner has 1980 shares
     */

    /*----------------------------MODIFIERS--------------------------*/

    modifier aliceApprovesVault() {
        vm.prank(alice);
        mockERC20.approve(address(vault), type(uint256).max);
        _;
    }

    modifier aliceLimitedApprovesVault() {
        vm.prank(alice);
        mockERC20.approve(address(vault), ALICE_LIMITED_APPROVAL);
        _;
    }

    modifier aliceDeposits30K() {
        vm.prank(alice);
        vault.deposit(ALICE_DEPOSIT, alice);
        _;
    }

    modifier aliceApproveBobFor5000Shares() {
        vm.prank(alice);
        vault.approve(bob, 5000);
        _;
    }

    /*-------------------------TEST FUNCTIONS-------------------------*/

    function test_maxDeposit() public view {
        assertEq(vault.maxDeposit(), type(uint256).max);
    }

    function test_maxMint() public view {
        assertEq(vault.maxMint(), type(uint256).max);
    }

    function test_maxWithdraw() public aliceApprovesVault aliceDeposits30K {
        vm.prank(alice);
        assertEq(vault.maxWithdraw(), 29400);
    }

    function test_maxRedeem() public aliceApprovesVault aliceDeposits30K {
        vm.prank(alice);
        assertEq(vault.maxRedeem(), vault.balanceOf(alice));
    }

    function test_totalAssets() public view {
        assertEq(vault.totalAssets(), INITIAL_VAULT_ASSETS);
        assertEq(vault.totalShares(), INITIAL_VAULT_ASSETS / 5);
    }

    // deposit
    function testRevert_sharesEqualZero() public aliceApprovesVault {
        vm.prank(alice);
        vm.expectRevert(Errors.ERC4626__InsufficientAssets.selector);
        vault.deposit(5, alice);
    }

    function testRevert_allowanceInsufficient()
        public
        aliceLimitedApprovesVault
    {
        vm.prank(alice);
        vm.expectRevert(stdError.arithmeticError);
        vault.deposit(ALICE_DEPOSIT, alice);
    }

    function testRevert_insufficientBalance()
        public
        aliceApprovesVault
        aliceDeposits30K
    {
        vm.startPrank(alice);
        mockERC20.approve(address(vault), type(uint256).max);
        vm.expectRevert(stdError.arithmeticError);
        vault.deposit(ALICE_INITIAL_TOKENS, alice);
    }

    function testRevert_InvalidReceiverForDeposit() public aliceApprovesVault {
        vm.expectRevert(Errors.ERC4626__InvalidReceiver.selector);
        vm.prank(alice);
        vault.deposit(ALICE_DEPOSIT, INVALID_RECEIVER);
    }

    function test_depositSuccessful()
        public
        aliceApprovesVault
        aliceDeposits30K
    {
        assertEq(vault.totalAssets(), INITIAL_VAULT_ASSETS + ALICE_DEPOSIT);
        assertEq(
            vault.totalShares(),
            (INITIAL_VAULT_ASSETS + ALICE_DEPOSIT) / 5 // since the total shares after 2 deposits still follow the same ration
        );
        assertEq(
            mockERC20.balanceOf(alice),
            ALICE_INITIAL_TOKENS - ALICE_DEPOSIT
        );
        assertEq(
            vault.balanceOf(alice),
            ALICE_DEPOSIT / 5 - ((ALICE_DEPOSIT / 5) / 100)
        );
    }

    // mint
    function testRevert_needMoreAssets() public aliceApprovesVault {
        vm.prank(alice);
        vm.expectRevert(Errors.ERC4626__InsufficientAssets.selector);
        vault.mint(INITIAL_VAULT_ASSETS + 1, alice);
    }

    function testRevert_limitedAllowance() public aliceLimitedApprovesVault {
        vm.prank(alice);
        vm.expectRevert(stdError.arithmeticError);
        vault.mint(ALICE_DEPOSIT / 5, alice);
    }

    function testRevert_InvalidReceiverForMint() public aliceApprovesVault {
        vm.prank(alice);
        vm.expectRevert(Errors.ERC4626__InvalidReceiver.selector);
        vault.mint(ALICE_DEPOSIT / 5, INVALID_RECEIVER);
    }

    function test_MintSuccessful() public aliceApprovesVault {
        uint256 aliceAssets = mockERC20.balanceOf(alice);
        uint256 vault_assets = vault.totalAssets();
        uint256 sum = aliceAssets + vault_assets;

        vm.prank(alice);
        vault.mint(ALICE_DEPOSIT / 5, alice);

        aliceAssets -= ALICE_DEPOSIT;
        vault_assets = vault.totalAssets();

        assertLt(sum, aliceAssets + vault_assets); // alice put in more assets to compensate fees
    }

    // withdraw
    function testRevert_insufficientShares()
        public
        aliceApprovesVault
        aliceDeposits30K
    {
        vm.prank(alice);
        vm.expectRevert(Errors.ERC4626__InsufficientShareBalance.selector);
        vault.withdraw(ALICE_DEPOSIT, alice, alice);
    }

    function testRevert_noShareAllowance()
        public
        aliceApprovesVault
        aliceDeposits30K
    {
        vm.prank(bob);
        vm.expectRevert(Errors.ERC4626__NotApprovedToSpendShares.selector);
        vault.withdraw(ALICE_LIMITED_APPROVAL, alice, alice);
    }

    function testRevert_InvalidReceiverForWithdraw()
        public
        aliceApprovesVault
        aliceDeposits30K
        aliceApproveBobFor5000Shares
    {
        vm.prank(bob);
        vm.expectRevert(Errors.ERC4626__InvalidReceiver.selector);
        vault.withdraw(ALICE_LIMITED_APPROVAL, INVALID_RECEIVER, alice);
    }

    function test_aliceWithdrawsAlicesShares()
        public
        aliceApprovesVault
        aliceDeposits30K
    {
        vm.prank(alice);
        vault.withdraw(ALICE_LIMITED_APPROVAL, alice, alice);
        assertLt(mockERC20.balanceOf(alice), ALICE_INITIAL_TOKENS);
        assertLt(vault.balanceOf(alice), ALICE_DEPOSIT / 5);
    }

    function test_bobWithdrawsAlicesShares()
        public
        aliceApprovesVault
        aliceDeposits30K
        aliceApproveBobFor5000Shares
    {
        vm.prank(bob);
        vault.withdraw(ALICE_LIMITED_APPROVAL, alice, alice);
        assertLt(mockERC20.balanceOf(alice), ALICE_INITIAL_TOKENS);
        assertLt(vault.balanceOf(alice), ALICE_DEPOSIT / 5);
    }

    //redeem
    function testRevert_insufficientShareBalance()
        public
        aliceApprovesVault
        aliceDeposits30K
    {
        vm.prank(alice);
        vm.expectRevert(Errors.ERC4626__InsufficientShareBalance.selector);
        vault.redeem(ALICE_DEPOSIT / 5, alice, alice);
    }

    function testRevert_notEnoughAllowanceToRedeemShares()
        public
        aliceApprovesVault
        aliceDeposits30K
        aliceApproveBobFor5000Shares
    {
        vm.prank(bob);
        vm.expectRevert(Errors.ERC4626__NotApprovedToSpendShares.selector);
        vault.redeem(5500, bob, alice);
    }

    function testRevert_InvalidReceiverForRedeem()
        public
        aliceApprovesVault
        aliceDeposits30K
    {
        vm.prank(alice);
        vm.expectRevert(Errors.ERC4626__InvalidReceiver.selector);
        vault.redeem(5000, INVALID_RECEIVER, alice);
    }

    function test_AliceReedemsAlicesShares()
        public
        aliceApprovesVault
        aliceDeposits30K
    {
        vm.prank(alice);
        vault.redeem(5000, bob, alice);

        assertGt(mockERC20.balanceOf(bob), 0);
        assertGt(ALICE_DEPOSIT / 6, vault.balanceOf(alice));
    }

    function test_bobReedemsAlicesShares()
        public
        aliceApprovesVault
        aliceDeposits30K
        aliceApproveBobFor5000Shares
    {
        vm.prank(bob);
        vault.redeem(5000, bob, alice);

        assertGt(mockERC20.balanceOf(bob), 0);
        assertGt(ALICE_DEPOSIT / 6, vault.balanceOf(alice));
    }

    //onlyowner

    //fees
    function testRevert_nonOwnerSetsFee() public {
        vm.expectRevert(Errors.ERC4626_OnlyOwnerCanSetFees.selector);
        vm.prank(alice);
        vault.setFee(300);
        assertEq(vault.getFee(), 100);
    }

    function testRevert_ownerSetsHighFee() public {
        assertEq(vault.getFee(), 100);
        vm.expectRevert(Errors.ERC4626_FeeTooHigh.selector);
        vm.prank(owner);
        vault.setFee(600);
        assertEq(vault.getFee(), 100);
    }

    function test_ownerSetsFee() public {
        assertEq(vault.getFee(), 100);
        vm.prank(owner);
        vault.setFee(300);
        assertEq(vault.getFee(), 300);
    }

    //withdraw assets owned by vault
    function testRevert_nonOwnerTriesToWithdrawAssets() public {
        uint256 vaultAssets = vault.totalAssets();
        uint256 vaultShares = vault.totalShares();
        vm.expectRevert(Errors.ERC4626_OnlyOwnerCanSetFees.selector);
        vm.prank(alice);
        vault.withdrawVaultAssets();
        assertEq(vault.totalAssets(), vaultAssets);
        assertEq(vault.totalShares(), vaultShares);
    }

    function test_OwnerWithdrawsAssetsOwnedByVault() public {
        uint256 totalSharesBeforeWithdraw = vault.totalShares();
        uint256 totalAssetsBeforeWithdraw = vault.totalAssets();
        uint256 assetTokensOwnedByOwnerBeforeWithdraw = mockERC20.balanceOf(
            owner
        );

        vm.prank(owner);
        vault.withdrawVaultAssets();

        assertLt(vault.totalShares(), totalSharesBeforeWithdraw);
        assertLt(vault.totalAssets(), totalAssetsBeforeWithdraw);
        assertEq(vault.balanceOf(address(vault)), 0);
        assertGt(
            mockERC20.balanceOf(owner),
            assetTokensOwnedByOwnerBeforeWithdraw
        );
    }

    function test_getUnderlyingAsset() public view {
        assertEq(vault.getUnderlyingAsset(), address(mockERC20));
    }

    function test_ERC20Metadata() public view {
        assertEq(vault.name(), "MyVault");
        assertEq(vault.symbol(), "MV");
        assertEq(vault.decimals(), 18);
        assertEq(vault.totalSupply(), vault.totalShares());
    }

    function test_nonces() public {
        vm.startPrank(alice);
        mockERC20.approve(address(vault), ALICE_INITIAL_TOKENS);
        vault.deposit(25_000, alice);
        vault.mint(10, alice);
        vault.withdraw(10_000, alice, alice);
        vault.redeem(10, alice, alice);
        vm.stopPrank();
    }
}
