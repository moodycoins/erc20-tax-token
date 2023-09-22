// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/ERC20SwapTax.sol";

contract DeployTestnet is Script {
    function run() external {
        vm.selectFork(vm.createFork(vm.envString("GOERLI_RPC_URL")));

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        new ERC20SwapTax(
            "ERC20 Tax Token",
            "TAX",
            5_000_000,
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
            msg.sender,
            1,
            1,
            1,
            false,
            false
        );

        vm.stopBroadcast();
    }
}