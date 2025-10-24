// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {VaultATFi} from "../src/VaultATFi.sol";

contract DeployVaultATFi is Script {
    VaultATFi public vaultAtfi;

    function run() external returns (address) {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        console.log("Deployer:", msg.sender);

        uint256 stakeAmount = 1 * 10**6; // 1 USDC
        uint256 registrationDeadline = block.timestamp + 1 days;
        uint256 eventDate = block.timestamp + 2 days;

        vaultAtfi = new VaultATFi(
            1, // eventId
            0x6b732552C0E06F69312D7E81969E28179E228C20, // organizer
            stakeAmount,
            registrationDeadline,
            eventDate,
            10 // maxParticipant
        );
        console.log("VaultATFi deployed at:", address(vaultAtfi));

        vm.stopBroadcast();

        return address(vaultAtfi);
    }
}