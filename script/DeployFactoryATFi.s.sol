// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {FactoryATFi} from "../src/FactoryATFi.sol";

contract DeployFactoryATFi is Script {
    FactoryATFi public factoryAtfi;

    function run() external returns (address) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        console.log("Deploying FactoryATFi...");

        vm.startBroadcast(privateKey);
        factoryAtfi = new FactoryATFi();
        vm.stopBroadcast();

        console.log("FactoryATFi deployed at:", address(factoryAtfi));

        return address(factoryAtfi);
    }
}