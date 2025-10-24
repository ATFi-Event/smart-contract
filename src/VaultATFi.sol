// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMorpho, Id} from "./interfaces/IMorpho.sol";

contract VaultATFi is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // PRD 2.5: ERC-4626 compliance with Morpho integration for yield generation
    IERC20 public constant ASSET_TOKEN = IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e);
    uint256 private constant BPS_PRECISION = 10000;
    address public treasury = 0x6b732552C0E06F69312D7E81969E28179E228C20;
    uint256 public protocolFeeBps = 500; // PRD 2.5: 5% protocol fee (500 bps)

    // Event specific data
    uint256 public eventId;
    address public organizer;
    uint256 public stakeAmount;
    uint256 public registrationDeadline;
    uint256 public eventDate;
    uint256 public maxParticipant;
    uint256 private eventSettlementTime;

    // Participant tracking
    struct Participant {
        bool hasDeposited;
        bool hasAttended;
        bool hasClaimed;
        uint256 claimableRewards;
    }

    mapping(address => Participant) public participants;
    address[] public participantAddresses;

    // Morpho integration
    IMorpho public morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    IMorpho.MarketParams public morphoMarketParams;
    Id public marketId;

    // Yield tracking
    uint256 public totalDepositedToYield;
    uint256 public totalYieldEarned;
    uint256 public totalNetYield;
    bool public depositedToYield;
    bool public eventSettled;

    event DepositMade(address indexed participant, uint256 amount);
    event AttendanceMarked(address indexed participant);
    event EventSettled(uint256 totalYield, uint256 protocolFee);
    event DepositToYieldSource(uint256 amount);
    event RewardClaimed(address indexed participant, uint256 rewardAmount);
    event MarketCreated(address indexed market, string message);
    event AssetApproved(address indexed token, uint256 amount, address indexed spender);
    event SupplyAttempted(uint256 amount, string message);

    constructor(
        uint256 _eventId,
        address _organizer,
        uint256 _stakeAmount,
        uint256 _registrationDeadline,
        uint256 _eventDate,
        uint256 _maxParticipant
    ) ERC20("ATFi Vault Share", "ATFi-VS") Ownable(_organizer) {
        require(_maxParticipant > 0, "Max participants must be greater than 0");
        eventId = _eventId;
        organizer = _organizer;
        stakeAmount = _stakeAmount;
        registrationDeadline = _registrationDeadline;
        eventDate = _eventDate;
        maxParticipant = _maxParticipant;

        morphoMarketParams = IMorpho.MarketParams({
            loanToken: address(ASSET_TOKEN),
            collateralToken: address(ASSET_TOKEN),
            oracle:0x2DC205F24BCb6B311E5cdf0745B0741648Aebd3d,
            irm: 0x46415998764C29aB2a25CbeA6254146D50D22687,
            lltv: 860000000000000000
        });
    }

    
    /**
     * @dev Peserta melakukan stake USDC untuk mendaftar event
     */
    function deposit() external nonReentrant {
        Participant storage user = participants[msg.sender];
        require(!user.hasDeposited, "Already deposited");
        require(block.timestamp < registrationDeadline, "Registration deadline passed");
        require(!eventSettled, "Event already settled");
        require(participantAddresses.length < maxParticipant, "Max participants reached");

        ASSET_TOKEN.safeTransferFrom(msg.sender, address(this), stakeAmount);
        _mint(msg.sender, stakeAmount);
        user.hasDeposited = true;
        participantAddresses.push(msg.sender);

        emit DepositMade(msg.sender, stakeAmount);
    }

    /**
     * @dev Deposit all assets to Morpho for yield generation
     */
    function depositToYieldSource() external onlyOwner {
        require(!depositedToYield, "Already deposited to yield");
        require(address(morpho) != address(0), "Morpho not set");
        require(totalAssets() > 0, "No assets to deposit");

        uint256 amountToDeposit = totalAssets();
        emit SupplyAttempted(amountToDeposit, "Starting deposit process");

        // Step 1: Approve Morpho to spend USDC
        try ASSET_TOKEN.approve(address(morpho), amountToDeposit) {
            emit AssetApproved(address(ASSET_TOKEN), amountToDeposit, address(morpho));
            emit SupplyAttempted(amountToDeposit, "USDC approval successful");
        } catch Error(string memory reason) {
            emit SupplyAttempted(amountToDeposit, string(abi.encodePacked("Approval failed: ", reason)));
            revert(string(abi.encodePacked("Approval failed: ", reason)));
        }

        // Step 2: Create market if needed
        try morpho.createMarket(morphoMarketParams) {
            emit MarketCreated(address(morpho), "Market created successfully");
            emit SupplyAttempted(amountToDeposit, "Market creation successful");
        } catch Error(string memory reason) {
            emit MarketCreated(address(morpho), string(abi.encodePacked("Market creation failed: ", reason)));
            emit SupplyAttempted(amountToDeposit, "Market might already exist, continuing");
        } catch {
            emit MarketCreated(address(morpho), "Market creation failed with unknown error, continuing");
        }

        // Step 3: Supply to Morpho
        try morpho.supply(morphoMarketParams, amountToDeposit, 0, address(this), "") {
            emit SupplyAttempted(amountToDeposit, "Supply to Morpho successful");
        } catch Error(string memory reason) {
            emit SupplyAttempted(amountToDeposit, string(abi.encodePacked("Supply failed: ", reason)));
            revert(string(abi.encodePacked("Supply failed: ", reason)));
        } catch {
            emit SupplyAttempted(amountToDeposit, "Supply failed with unknown error");
            revert("Supply to Morpho failed");
        }

        totalDepositedToYield = amountToDeposit;
        depositedToYield = true;
        emit DepositToYieldSource(amountToDeposit);
        emit SupplyAttempted(amountToDeposit, "Deposit process completed successfully");
    }

    
    
    /**
     * @dev Settle event and calculate reward for Attended Participants
     */
    function settleEvent(address[] calldata _attendedParticipants) external onlyOwner nonReentrant {
        require(depositedToYield, "Not yet deposited to yield");
        require(!eventSettled, "Event already settled");

        for (uint256 i = 0; i < _attendedParticipants.length; i++) {
            address participantAddr = _attendedParticipants[i];
            Participant storage user = participants[participantAddr];
            if (user.hasDeposited && !user.hasAttended) {
                user.hasAttended = true;
                emit AttendanceMarked(participantAddr);
            }
        }

        _withdrawAllFromYieldSource();

        // Calculate actual yield from Morpho (real balance - original deposited amount)
        uint256 currentBalance = ASSET_TOKEN.balanceOf(address(this));
        uint256 actualYieldEarned = currentBalance > totalDepositedToYield ? currentBalance - totalDepositedToYield : 0;
        totalYieldEarned = actualYieldEarned;

        // Take 5% of actual yield for treasury (skip if yield is 0)
        uint256 protocolFeeAmount = actualYieldEarned > 0 ? (actualYieldEarned * protocolFeeBps) / BPS_PRECISION : 0;
        totalNetYield = totalYieldEarned - protocolFeeAmount;

        if (protocolFeeAmount > 0) {
            ASSET_TOKEN.safeTransfer(treasury, protocolFeeAmount);
        }

        _calculateRewards();
        eventSettled = true;
        eventSettlementTime = block.timestamp;
        emit EventSettled(totalYieldEarned, protocolFeeAmount);
    }

    function _calculateYield() internal view returns (uint256) {
        if (depositedToYield && address(morpho) != address(0)) {
            // Simple fixed yield calculation (5% annually) for now
            return (totalDepositedToYield * 5) / 100;
        }
        return 0;
    }

        /**
     * @dev Internal function to withdraw from Morpho
     */
    function _withdrawFromMorpho(uint256 _amount) internal {
        require(address(morpho) != address(0), "Morpho not set");

        // Withdraw from Morpho
        morpho.withdraw(morphoMarketParams, _amount, 0, address(this), address(this));
    }

    function _withdrawAllFromYieldSource() internal {
        if (address(morpho) != address(0) && depositedToYield) {
            // Withdraw all assets from Morpho (use simple approach)
            _withdrawFromMorpho(totalDepositedToYield);
        }
    }

    function claimReward() external nonReentrant {
        Participant storage user = participants[msg.sender];
        require(user.hasDeposited, "Not a participant");
        require(user.hasAttended, "Did not attend");
        require(!user.hasClaimed, "Already claimed");
        require(eventSettled, "Event not settled");

        uint256 rewardAmount = user.claimableRewards;
        require(rewardAmount > 0, "No reward available");

        user.hasClaimed = true;

        if (totalAssets() < rewardAmount) {
            _withdrawAllFromYieldSource();
        }

        ASSET_TOKEN.safeTransfer(msg.sender, rewardAmount);

        emit RewardClaimed(msg.sender, rewardAmount);
    }

    /**
     * @dev Hitung reward untuk setiap peserta yang hadir
     * Formula: Stake Awal + ((Total No-Show Stake + Net Yield) / Jumlah Peserta Hadir)
     */
    function _calculateRewards() internal {
        uint256 attendedCount;
        uint256 totalNoShowStake;

        for (uint256 i = 0; i < participantAddresses.length; i++) {
            address participantAddr = participantAddresses[i];
            if (participants[participantAddr].hasAttended) {
                attendedCount++;
            } else {
                totalNoShowStake += stakeAmount;
            }
        }

        if (attendedCount == 0) return;

        uint256 bonusPerParticipant = (totalNoShowStake + totalNetYield) / attendedCount;

        for (uint256 i = 0; i < participantAddresses.length; i++) {
            address participantAddr = participantAddresses[i];
            Participant storage user = participants[participantAddr];
            if (user.hasAttended) {
                user.claimableRewards = stakeAmount + bonusPerParticipant;
            }
        }
    }

    // View functions for assets management
    function totalAssets() public view returns (uint256) {
        if (depositedToYield) {
            if (eventSettled) {
                // After settlement: actual balance is accurate (protocol fee already deducted)
                return ASSET_TOKEN.balanceOf(address(this));
            } else {
                // Before settlement: show gross assets (deposited + earned yield)
                return totalDepositedToYield + totalYieldEarned;
            }
        }
        return ASSET_TOKEN.balanceOf(address(this));
    }

    function maxDeposit(address) public view returns (uint256) {
        if (eventSettled || block.timestamp >= registrationDeadline) return 0;
        return stakeAmount;
    }

    function maxWithdraw(address _owner) public view returns (uint256) {
        Participant storage user = participants[_owner];
        if (!eventSettled || !user.hasClaimed) return 0;
        return user.claimableRewards;
    }

    // View functions
    function getParticipantCount() external view returns (uint256) {
        return participantAddresses.length;
    }

    function getUserReward(address _user) external view returns (uint256) {
        return participants[_user].claimableRewards;
    }
}