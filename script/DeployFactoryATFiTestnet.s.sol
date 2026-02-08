// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {FactoryATFi} from "../src/FactoryATFi.sol";

/**
 * @notice Deployment script for FactoryATFi on Base Sepolia Testnet
 * @dev Run with: forge script script/DeployFactoryATFiTestnet.s.sol:DeployFactoryATFiTestnet --rpc-url base_sepolia --broadcast --verify
 */
contract DeployFactoryATFiTestnet is Script {
    // Base Sepolia addresses
    address constant TREASURY = 0x6b732552C0E06F69312D7E81969E28179E228C20; // Same treasury (your address)
    address constant MORPHO_VAULT = address(0); // No Morpho on testnet - pass address(0)
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // Base Sepolia USDC

    FactoryATFi public factoryAtfi;

    function run() external returns (FactoryATFi) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        console.log("Deploying FactoryATFi to Base Sepolia...");
        console.log("Treasury:", TREASURY);
        console.log("Morpho Vault:", MORPHO_VAULT);
        console.log("USDC:", USDC);

        vm.startBroadcast(privateKey);

        // Deploy factory with address(0) for Morpho Vault (no yield on testnet)
        factoryAtfi = new FactoryATFi(TREASURY, MORPHO_VAULT, USDC);

        vm.stopBroadcast();

        console.log("FactoryATFi deployed at:", address(factoryAtfi));
        console.log("---");
        console.log("Update SDK addresses.ts with this factory address!");

        return factoryAtfi;
    }
}
