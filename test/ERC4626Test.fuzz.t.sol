// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ERC4626} from "src/ERC4626.sol";
import {ERC20} from "src/mocks/MockERC20.sol";
import {DeployVault} from "script/DeployERC4626.s.sol";
import {stdError} from "forge-std/StdError.sol";
import {Errors} from "../src/libraries/Errors.sol";

contract TestVault is Test {
    ERC20 mockERC20;
    ERC4626 vault;
    address payable alice = payable(makeAddr("alice"));
    address payable bob = payable(makeAddr("bob"));
    address private immutable owner = msg.sender;
    uint256 INITIAL_VAULT_ASSETS = 10_000;
    uint256 private constant ALICE_INITIAL_TOKENS = 90_000;
    uint256 private constant ALICE_DEPOSIT = 30_000;
    uint256 private constant ALICE_LIMITED_APPROVAL = 20_000;
    address private constant INVALID_RECEIVER = address(0);

    /**
     * @notice after every setup, alice has 10_000 assets and bob has none
     */
    function setUp() public {
        //Instantiating mockERC20 Token with owner owning 100_000 tokens
        mockERC20 = new ERC20("MocKERCToken", "MT", 6, owner);

        // Deploy Vault with mockERC20 as underlying asset
        DeployVault deployer = new DeployVault();
        vault = deployer.run(address(mockERC20));

        vm.startPrank(owner);
        // Owner does the following
        // 1. Provides initial seed to vault with 5 asset tokens in return for 1 share
        mockERC20.approve(address(vault), INITIAL_VAULT_ASSETS);
        vault.deposit(INITIAL_VAULT_ASSETS, owner);
        // 2. Transfer Alice 10_000 asset tokens for further testing
        mockERC20.transfer(alice, ALICE_INITIAL_TOKENS);
        vm.stopPrank();
    }

    function test_deposit(uint32 assets, address receiver) public {
        vm.assume((assets > 9) && (assets < ALICE_INITIAL_TOKENS));
        vm.assume((receiver != address(0)) && (receiver != address(vault)));

        uint256 totalAssetsBeforeDeposit = mockERC20.balanceOf(alice) + mockERC20.balanceOf(address(vault));

        vm.startPrank(alice);
        mockERC20.approve(address(vault), assets);
        vault.deposit(assets, receiver);

        assertEq(vault.totalAssets(), assets + INITIAL_VAULT_ASSETS);
        assertEq(mockERC20.balanceOf(alice) + mockERC20.balanceOf(address(vault)), totalAssetsBeforeDeposit);
    }

    function test_mint(uint16 shares, address receiver) public {
        vm.assume(shares < ALICE_INITIAL_TOKENS / 6);
        vm.assume((receiver != address(0)) && (receiver != address(vault)));

        uint256 aliceAssetsBefore = mockERC20.balanceOf(alice);
        uint256 vaultAssetsBefore = mockERC20.balanceOf(address(vault));

        vm.startPrank(alice);
        mockERC20.approve(address(vault), ALICE_INITIAL_TOKENS);
        vault.mint(shares, receiver);
        vm.stopPrank();

        uint256 aliceAssetsAfter = mockERC20.balanceOf(alice);
        uint256 vaultAssetsAfter = mockERC20.balanceOf(address(vault));

        assertEq(aliceAssetsBefore - aliceAssetsAfter, vaultAssetsAfter - vaultAssetsBefore);
    }

    function test_withdraw(uint32 assets, address receiver) public {
        vm.assume(assets < ALICE_INITIAL_TOKENS - 1800);
        vm.assume((receiver != address(0)) && (receiver != address(vault)));

        vm.startPrank(alice);
        mockERC20.approve(address(vault), ALICE_INITIAL_TOKENS);
        vault.deposit(ALICE_INITIAL_TOKENS, alice);
        vault.approve(bob, type(uint256).max);
        vm.stopPrank();

        uint256 vaultAssetsBefore = mockERC20.balanceOf(address(vault));

        vm.prank(bob);
        vault.withdraw(assets, receiver, alice);

        uint256 vaultAssetsAfter = mockERC20.balanceOf(address(vault));
        uint256 receiverAssets = mockERC20.balanceOf(receiver);

        assertEq(receiverAssets, vaultAssetsBefore - vaultAssetsAfter);
    }

    function test_redeem(uint32 shares, address receiver) public {
        vm.assume(shares < ALICE_INITIAL_TOKENS / 6);
        vm.assume((receiver != address(0)) && (receiver != address(vault)));

        vm.startPrank(alice);
        mockERC20.approve(address(vault), ALICE_INITIAL_TOKENS);
        vault.deposit(ALICE_INITIAL_TOKENS, alice);
        vault.approve(bob, type(uint256).max);
        vm.stopPrank();

        uint256 vaultAssetsBefore = mockERC20.balanceOf(address(vault));

        vm.prank(bob);
        vault.redeem(shares, receiver, alice);

        uint256 vaultAssetsAfter = mockERC20.balanceOf(address(vault));
        uint256 receiverAssets = mockERC20.balanceOf(receiver);

        assertEq(receiverAssets, vaultAssetsBefore - vaultAssetsAfter);
    }
}
