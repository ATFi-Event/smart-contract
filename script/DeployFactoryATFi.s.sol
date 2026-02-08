// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {FactoryATFi} from "../src/FactoryATFi.sol";

contract DeployFactoryATFi is Script {
    // Base Mainnet addresses
    address constant TREASURY = 0x6b732552C0E06F69312D7E81969E28179E228C20;
    address constant MORPHO_VAULT = 0x050cE30b927Da55177A4914EC73480238BAD56f0;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    FactoryATFi public factoryAtfi;

    function run() external returns (FactoryATFi) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);

        factoryAtfi = new FactoryATFi(TREASURY, MORPHO_VAULT, USDC);

        vm.stopBroadcast();

        return factoryAtfi;
    }
}
