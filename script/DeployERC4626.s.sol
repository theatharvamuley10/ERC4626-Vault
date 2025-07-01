// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {ERC4626} from "src/ERC4626.sol";

contract DeployVault is Script {
    function run(address underlyingAssetContract) external returns (ERC4626) {
        vm.startBroadcast();
        ERC4626 vault = new ERC4626(
            underlyingAssetContract,
            "MyVault",
            "MV",
            8
        );
        vm.stopBroadcast();
        return vault;
    }
}
