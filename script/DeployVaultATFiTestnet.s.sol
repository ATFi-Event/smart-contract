// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {FactoryATFi} from "../src/FactoryATFi.sol";
import {VaultATFi} from "../src/VaultATFi.sol";

/**
 * @notice Script to create a test vault on Base Sepolia via the factory
 * @dev Run with: forge script script/DeployVaultATFiTestnet.s.sol:CreateVaultATFiTestnet --rpc-url base_sepolia --broadcast
 */
contract CreateVaultATFiTestnet is Script {
    // Base Sepolia FactoryATFi address (UPDATE after deployment)
    address constant FACTORY = address(0xf1EA206029549A8c4e2EB960F7ac43A98E922A49); // TODO: Update with deployed factory address

    // Base Sepolia USDC address
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    function run() external returns (address) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        require(
            FACTORY != address(0),
            "Set FACTORY address first after deploying FactoryATFi"
        );

        FactoryATFi factory = FactoryATFi(FACTORY);

        console.log("Creating test vault on Base Sepolia...");
        console.log("Factory:", FACTORY);
        console.log("Token:", USDC);

        // Test vault parameters
        uint256 stakeAmount = 1 * 10 ** 6; // 1 USDC (small amount for testing)
        uint256 maxParticipants = 10; // Small group for testing

        vm.startBroadcast(privateKey);

        // Create vault (no yield on testnet since Morpho = address(0))
        uint256 vaultId = factory.createVault(
            USDC,
            stakeAmount,
            maxParticipants
        );

        vm.stopBroadcast();

        address vaultAddr = factory.getVault(vaultId);

        console.log("---");
        console.log("Vault ID:", vaultId);
        console.log("VaultATFi deployed at:", vaultAddr);
        console.log("Stake amount: 1 USDC");
        console.log("Max participants: 10");
        console.log("---");
        console.log("Note: Yield is DISABLED on testnet (Morpho = address(0))");

        return vaultAddr;
    }
}
