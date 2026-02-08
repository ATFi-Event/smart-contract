// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {FactoryATFi} from "../src/FactoryATFi.sol";
import {VaultATFi} from "../src/VaultATFi.sol";

/**
 * @notice Script to create a vault via the factory
 * @dev Vaults should be created through FactoryATFi, not deployed directly
 */
contract CreateVaultATFi is Script {
    // Base Mainnet FactoryATFi address (set after deployment)
    address constant FACTORY = address(0x0bE05a5fA7116C1B33f2B0036Eb0d9690DB9075F);

    // Base Mainnet USDC address
    address constant USDC = address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    function run() external returns (address) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        require(FACTORY != address(0), "Set FACTORY address first");

        FactoryATFi factory = FactoryATFi(FACTORY);

        console.log("Creating vault via FactoryATFi...");

        uint256 stakeAmount = 10 * 10**6; // 10 USDC
        uint256 maxParticipants = 50;

        vm.startBroadcast(privateKey);

        // Create vault with Morpho yield (USDC only for yield mode)
        uint256 vaultId = factory.createVault(
            USDC,
            stakeAmount,
            maxParticipants
        );
        
        vm.stopBroadcast();

        address vaultAddr = factory.getVault(vaultId);
        
        console.log("Vault ID:", vaultId);
        console.log("VaultATFi deployed at:", vaultAddr);

        return vaultAddr;
    }
}