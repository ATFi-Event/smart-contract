// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VaultATFi} from "./VaultATFi.sol";

/**
 * @title FactoryATFi
 * @dev Minimal factory contract untuk membuat VaultATFi
 * @author ATFi Team
 */
contract FactoryATFi {
    event VaultCreated(uint256 indexed eventId, address indexed vault, address indexed organizer, uint256 stakeAmount, uint256 maxParticipant, uint256 registrationDeadline, uint256 eventDate);

    mapping(address => bool) public isVault;
    uint256 public eventIdCounter = 1;

    function createEvent(
        uint256 stakeAmount,
        uint256 registrationDeadline,
        uint256 eventDate,
        uint256 maxParticipant
    ) external returns (uint256) {
        require(registrationDeadline < eventDate, "Invalid deadline");
        require(registrationDeadline > block.timestamp, "Deadline in past");
        require(stakeAmount > 0, "Invalid stake amount");
        require(maxParticipant > 0, "Invalid max participants");

        uint256 newEventId = eventIdCounter;

        VaultATFi vault = new VaultATFi(newEventId, msg.sender, stakeAmount, registrationDeadline, eventDate, maxParticipant);
        address vaultAddress = address(vault);
        isVault[vaultAddress] = true;

        emit VaultCreated(newEventId, vaultAddress, msg.sender, stakeAmount, maxParticipant, registrationDeadline, eventDate);

        eventIdCounter++;

        return newEventId;
    }

    // Check if address is a valid vault
    function isValidVault(address vault) external view returns (bool) {
        return isVault[vault];
    }
}