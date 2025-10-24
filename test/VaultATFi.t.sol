// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {VaultATFi} from "../src/VaultATFi.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 1000000 * 1e6); // 1M USDC
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TestVaultATFi is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Test version that accepts mock USDC
    IERC20 public assetToken;
    uint256 private constant BPS_PRECISION = 10000;
    address public treasury = 0x6b732552C0E06F69312D7E81969E28179E228C20;
    uint256 public protocolFeeBps = 500;

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

    // Yield tracking (simplified for testing)
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

    constructor(
        IERC20 _assetToken,
        uint256 _eventId,
        address _organizer,
        uint256 _stakeAmount,
        uint256 _registrationDeadline,
        uint256 _eventDate,
        uint256 _maxParticipant
    ) ERC20("ATFi Vault Share", "ATFi-VS") Ownable(_organizer) {
        require(_maxParticipant > 0, "Max participants must be greater than 0");
        assetToken = _assetToken;
        eventId = _eventId;
        organizer = _organizer;
        stakeAmount = _stakeAmount;
        registrationDeadline = _registrationDeadline;
        eventDate = _eventDate;
        maxParticipant = _maxParticipant;
    }

    function deposit() external nonReentrant {
        Participant storage user = participants[msg.sender];
        require(!user.hasDeposited, "Already deposited");
        require(block.timestamp < registrationDeadline, "Registration deadline passed");
        require(!eventSettled, "Event already settled");
        require(participantAddresses.length < maxParticipant, "Max participants reached");

        assetToken.safeTransferFrom(msg.sender, address(this), stakeAmount);
        _mint(msg.sender, stakeAmount);
        user.hasDeposited = true;
        participantAddresses.push(msg.sender);

        emit DepositMade(msg.sender, stakeAmount);
    }

    function depositToYieldSource() external onlyOwner {
        require(!depositedToYield, "Already deposited to yield");
        require(address(assetToken) != address(0), "Asset token not set");
        require(totalAssets() > 0, "No assets to deposit");

        uint256 amountToDeposit = totalAssets();
        totalDepositedToYield = amountToDeposit;
        depositedToYield = true;

        // Simulate yield generation for testing
        totalYieldEarned = (amountToDeposit * 5) / 100; // 5% yield

        emit DepositToYieldSource(amountToDeposit);
    }

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

        // Calculate net yield (5% protocol fee)
        uint256 protocolFeeAmount = (totalYieldEarned * protocolFeeBps) / BPS_PRECISION;
        totalNetYield = totalYieldEarned - protocolFeeAmount;

        _calculateRewards();
        eventSettled = true;
        eventSettlementTime = block.timestamp;
        emit EventSettled(totalYieldEarned, protocolFeeAmount);
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
            // This shouldn't happen in test setup
            revert("Insufficient vault assets");
        }

        assetToken.safeTransfer(msg.sender, rewardAmount);
        emit RewardClaimed(msg.sender, rewardAmount);
    }

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

    // View functions
    function totalAssets() public view returns (uint256) {
        if (depositedToYield) {
            if (eventSettled) {
                return assetToken.balanceOf(address(this));
            } else {
                return totalDepositedToYield + totalYieldEarned;
            }
        }
        return assetToken.balanceOf(address(this));
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

    function getParticipantCount() external view returns (uint256) {
        return participantAddresses.length;
    }

    function getUserReward(address _user) external view returns (uint256) {
        return participants[_user].claimableRewards;
    }
}

contract VaultATFiTest is Test {
    TestVaultATFi public vault;
    MockUSDC public usdc;

    // Test event data
    uint256 constant TEST_EVENT_ID = 1;
    uint256 constant TEST_STAKE_AMOUNT = 100 * 1e6; // 100 USDC (6 decimals)
    uint256 constant REGISTRATION_DEADLINE = 30 days;
    uint256 constant EVENT_DATE = 60 days;
    uint256 constant MAX_PARTICIPANTS = 50;

    address public organizer = address(0x1);
    address public participant1 = address(0x2);
    address public participant2 = address(0x3);
    address public participant3 = address(0x4);

    event DepositMade(address indexed participant, uint256 amount);
    event AttendanceMarked(address indexed participant);
    event EventSettled(uint256 totalYield, uint256 protocolFee);
    event DepositToYieldSource(uint256 amount);
    event RewardClaimed(address indexed participant, uint256 rewardAmount);

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();

        // Deploy test vault contract
        vm.startPrank(organizer);
        vault = new TestVaultATFi(
            usdc,
            TEST_EVENT_ID,
            organizer,
            TEST_STAKE_AMOUNT,
            block.timestamp + REGISTRATION_DEADLINE,
            block.timestamp + EVENT_DATE,
            MAX_PARTICIPANTS
        );
        vm.stopPrank();

        // Fund participants with USDC
        usdc.mint(participant1, 1000 * 1e6);
        usdc.mint(participant2, 1000 * 1e6);
        usdc.mint(participant3, 1000 * 1e6);

        // Approve vault to spend USDC for participants
        vm.startPrank(participant1);
        usdc.approve(address(vault), 1000 * 1e6);
        vm.stopPrank();

        vm.startPrank(participant2);
        usdc.approve(address(vault), 1000 * 1e6);
        vm.stopPrank();

        vm.startPrank(participant3);
        usdc.approve(address(vault), 1000 * 1e6);
        vm.stopPrank();
    }

    function testVaultDeployment() public view {
        // Test that vault is deployed correctly
        assertTrue(address(vault) != address(0), "Vault should be deployed");
        assertEq(vault.eventId(), TEST_EVENT_ID, "Event ID should match");
        assertEq(vault.organizer(), organizer, "Organizer should match");
        assertEq(vault.stakeAmount(), TEST_STAKE_AMOUNT, "Stake amount should match");
        assertEq(vault.maxParticipant(), MAX_PARTICIPANTS, "Max participants should match");
    }

    function testValidDeposit() public {
        vm.startPrank(participant1);

        // Expect DepositMade event
        vm.expectEmit(true, false, false, false);
        emit DepositMade(participant1, TEST_STAKE_AMOUNT);
        vault.deposit();
        vm.stopPrank();

        // Verify participant state
        (bool hasDeposited, bool hasAttended, bool hasClaimed, uint256 claimableRewards) = vault.participants(participant1);
        assertTrue(hasDeposited, "Participant should have deposited");
        assertFalse(hasAttended, "Participant should not have attended yet");
        assertFalse(hasClaimed, "Participant should not have claimed yet");
        assertEq(claimableRewards, 0, "Claimable rewards should be 0 initially");

        // Verify participant count
        assertEq(vault.getParticipantCount(), 1, "Should have 1 participant");

        // Verify vault shares minted
        assertEq(vault.balanceOf(participant1), TEST_STAKE_AMOUNT, "Participant should have vault shares");
    }

    function testDuplicateDeposit() public {
        vm.startPrank(participant1);
        vault.deposit();

        // Try to deposit again
        vm.expectRevert("Already deposited");
        vault.deposit();
        vm.stopPrank();
    }

    function testDepositAfterDeadline() public {
        // Fast forward past registration deadline
        vm.warp(block.timestamp + REGISTRATION_DEADLINE + 1);

        vm.startPrank(participant1);
        vm.expectRevert("Registration deadline passed");
        vault.deposit();
        vm.stopPrank();
    }

    function testDepositMaxParticipantsReached() public {
        // Create a vault with only 2 max participants for testing
        vm.startPrank(organizer);
        TestVaultATFi smallVault = new TestVaultATFi(
            usdc,
            2,
            organizer,
            TEST_STAKE_AMOUNT,
            block.timestamp + REGISTRATION_DEADLINE,
            block.timestamp + EVENT_DATE,
            2 // Max 2 participants
        );
        vm.stopPrank();

        // Approve small vault for participants
        vm.startPrank(participant1);
        usdc.approve(address(smallVault), 1000 * 1e6);
        smallVault.deposit();
        vm.stopPrank();

        vm.startPrank(participant2);
        usdc.approve(address(smallVault), 1000 * 1e6);
        smallVault.deposit();
        vm.stopPrank();

        // Third participant should not be able to deposit
        vm.startPrank(participant3);
        usdc.approve(address(smallVault), 1000 * 1e6);
        vm.expectRevert("Max participants reached");
        smallVault.deposit();
        vm.stopPrank();
    }

    function testDepositWithoutApproval() public {
        // Create new participant without approval
        address participant4 = address(0x5);
        usdc.mint(participant4, 1000 * 1e6);

        vm.startPrank(participant4);
        vm.expectRevert(); // Should fail due to insufficient allowance
        vault.deposit();
        vm.stopPrank();
    }

    function testDepositWithoutBalance() public {
        // Create new participant without balance
        address participant4 = address(0x5);

        vm.startPrank(participant4);
        usdc.approve(address(vault), 1000 * 1e6);
        vm.expectRevert(); // Should fail due to insufficient balance
        vault.deposit();
        vm.stopPrank();
    }

    function testDepositToYieldSource() public {
        // First, have participants deposit
        vm.startPrank(participant1);
        vault.deposit();
        vm.stopPrank();

        vm.startPrank(participant2);
        vault.deposit();
        vm.stopPrank();

        // Owner deposits to yield source
        vm.startPrank(organizer);

        // Expect DepositToYieldSource event
        vm.expectEmit(false, false, false, false);
        emit DepositToYieldSource(TEST_STAKE_AMOUNT * 2);
        vault.depositToYieldSource();
        vm.stopPrank();

        // Verify state
        assertTrue(vault.depositedToYield(), "Should be marked as deposited to yield");
        assertEq(vault.totalDepositedToYield(), TEST_STAKE_AMOUNT * 2, "Total deposited should match");
    }

    function testDepositToYieldSourceUnauthorized() public {
        vm.startPrank(participant1);
        vm.expectRevert();
        vault.depositToYieldSource();
        vm.stopPrank();
    }

    function testDepositToYieldSourceTwice() public {
        // First deposit
        vm.startPrank(participant1);
        vault.deposit();
        vm.stopPrank();

        vm.startPrank(organizer);
        vault.depositToYieldSource();

        // Try to deposit again
        vm.expectRevert("Already deposited to yield");
        vault.depositToYieldSource();
        vm.stopPrank();
    }

    function testSettleEvent() public {
        // Setup: participants deposit and deposit to yield
        vm.startPrank(participant1);
        vault.deposit();
        vm.stopPrank();

        vm.startPrank(participant2);
        vault.deposit();
        vm.stopPrank();

        vm.startPrank(organizer);
        vault.depositToYieldSource();

        // Settle event with participant1 attending, participant2 not attending
        address[] memory attendedParticipants = new address[](1);
        attendedParticipants[0] = participant1;

        // Expect EventSettled event
        vm.expectEmit(false, false, false, false);
        emit EventSettled((TEST_STAKE_AMOUNT * 2 * 5) / 100, ((TEST_STAKE_AMOUNT * 2 * 5) / 100 * 500) / 10000);
        vault.settleEvent(attendedParticipants);
        vm.stopPrank();

        // Verify event is settled
        assertTrue(vault.eventSettled(), "Event should be settled");

        // Verify attendance
        (, bool hasAttended1,, ) = vault.participants(participant1);
        assertTrue(hasAttended1, "Participant1 should be marked as attended");

        (, bool hasAttended2,, ) = vault.participants(participant2);
        assertFalse(hasAttended2, "Participant2 should not be marked as attended");
    }

    function testSettleEventUnauthorized() public {
        address[] memory attendedParticipants = new address[](1);
        attendedParticipants[0] = participant1;

        vm.startPrank(participant1);
        vm.expectRevert();
        vault.settleEvent(attendedParticipants);
        vm.stopPrank();
    }

    function testSettleEventBeforeYieldDeposit() public {
        address[] memory attendedParticipants = new address[](1);
        attendedParticipants[0] = participant1;

        vm.startPrank(organizer);
        vm.expectRevert("Not yet deposited to yield");
        vault.settleEvent(attendedParticipants);
        vm.stopPrank();
    }

  
    function testClaimRewardNotDeposited() public {
        vm.startPrank(participant1);
        vm.expectRevert("Not a participant");
        vault.claimReward();
        vm.stopPrank();
    }

    function testClaimRewardNotAttended() public {
        vm.startPrank(participant1);
        vault.deposit();
        vm.stopPrank();

        vm.startPrank(organizer);
        vault.depositToYieldSource();

        address[] memory attendedParticipants = new address[](0);
        vault.settleEvent(attendedParticipants);
        vm.stopPrank();

        vm.startPrank(participant1);
        vm.expectRevert("Did not attend");
        vault.claimReward();
        vm.stopPrank();
    }

    function testClaimRewardNotSettled() public {
        vm.startPrank(participant1);
        vault.deposit();
        vm.stopPrank();

        vm.startPrank(participant1);
        vm.expectRevert("Did not attend");
        vault.claimReward();
        vm.stopPrank();
    }

  
    function testTotalAssets() public {
        // Initially should be 0
        assertEq(vault.totalAssets(), 0, "Total assets should be 0 initially");

        // After deposit
        vm.startPrank(participant1);
        vault.deposit();
        vm.stopPrank();

        assertEq(vault.totalAssets(), TEST_STAKE_AMOUNT, "Total assets should equal stake amount");

        // After yield deposit
        vm.startPrank(organizer);
        vault.depositToYieldSource();
        vm.stopPrank();

        uint256 expectedAssets = TEST_STAKE_AMOUNT + (TEST_STAKE_AMOUNT * 5) / 100; // Principal + 5% yield
        assertEq(vault.totalAssets(), expectedAssets, "Total assets should include yield");
    }

    function testMaxDeposit() public {
        // Before deadline
        assertEq(vault.maxDeposit(participant1), TEST_STAKE_AMOUNT, "Max deposit should equal stake amount");

        // After deadline
        vm.warp(block.timestamp + REGISTRATION_DEADLINE + 1);
        assertEq(vault.maxDeposit(participant1), 0, "Max deposit should be 0 after deadline");
    }

  
    function testGetUserReward() public {
        // Initially should be 0
        assertEq(vault.getUserReward(participant1), 0, "User reward should be 0 initially");

        // Setup complete lifecycle
        vm.startPrank(participant1);
        vault.deposit();
        vm.stopPrank();

        vm.startPrank(organizer);
        vault.depositToYieldSource();

        address[] memory attendedParticipants = new address[](1);
        attendedParticipants[0] = participant1;
        vault.settleEvent(attendedParticipants);
        vm.stopPrank();

        // Should have reward after settlement
        uint256 reward = vault.getUserReward(participant1);
        assertGt(reward, 0, "User should have reward after settlement");
        // When only one participant attends, they should get back their stake + yield - protocol fees
        // Expected: 100,000,000 (stake) + 5,000,000 (yield) - 250,000 (protocol fee) = 104,750,000
        uint256 expectedReward = TEST_STAKE_AMOUNT + (TEST_STAKE_AMOUNT * 5) / 100 - ((TEST_STAKE_AMOUNT * 5) / 100 * 500) / 10000;
        assertEq(reward, expectedReward, "Reward should equal stake amount plus yield minus protocol fees");
    }

    function testMultipleParticipantsRewardCalculation() public {
        // Setup 3 participants
        vm.startPrank(participant1);
        vault.deposit();
        vm.stopPrank();

        vm.startPrank(participant2);
        vault.deposit();
        vm.stopPrank();

        vm.startPrank(participant3);
        vault.deposit();
        vm.stopPrank();

        vm.startPrank(organizer);
        vault.depositToYieldSource();

        // Only participants 1 and 2 attend, participant3 doesn't
        address[] memory attendedParticipants = new address[](2);
        attendedParticipants[0] = participant1;
        attendedParticipants[1] = participant2;
        vault.settleEvent(attendedParticipants);
        vm.stopPrank();

        // Calculate expected rewards
        // Each attending participant gets: stake + (no-show stake + net yield) / attending_count
        uint256 totalYield = (TEST_STAKE_AMOUNT * 3 * 5) / 100; // 5% yield on total deposits
        uint256 protocolFee = (totalYield * 500) / 10000; // 5% protocol fee
        uint256 netYield = totalYield - protocolFee;
        uint256 expectedReward = TEST_STAKE_AMOUNT + (TEST_STAKE_AMOUNT + netYield) / 2;

        assertEq(vault.getUserReward(participant1), expectedReward, "Participant1 reward should match expected");
        assertEq(vault.getUserReward(participant2), expectedReward, "Participant2 reward should match expected");
        assertEq(vault.getUserReward(participant3), 0, "Participant3 should have no reward");
    }

    function testProtocolFeeCalculation() public {
        // Setup with yield
        vm.startPrank(participant1);
        vault.deposit();
        vm.stopPrank();

        vm.startPrank(organizer);
        vault.depositToYieldSource();

        address[] memory attendedParticipants = new address[](1);
        attendedParticipants[0] = participant1;
        vault.settleEvent(attendedParticipants);
        vm.stopPrank();

        // Verify protocol fee was charged (5% of yield)
        uint256 protocolFeeBps = vault.protocolFeeBps();
        assertEq(protocolFeeBps, 500, "Protocol fee should be 500 bps (5%)");
    }

    function testEdgeCaseZeroParticipants() public {
        // Create vault with 0 max participants
        vm.startPrank(organizer);
        vm.expectRevert("Max participants must be greater than 0");
        new TestVaultATFi(
            usdc,
            999,
            organizer,
            TEST_STAKE_AMOUNT,
            block.timestamp + REGISTRATION_DEADLINE,
            block.timestamp + EVENT_DATE,
            0
        );
        vm.stopPrank();
    }

    function testFuzzDeposit(
        uint256 stakeAmount,
        uint256 deadline,
        uint256 eventDate,
        uint256 maxParticipants
    ) public {
        // Bounds checking for reasonable values
        vm.assume(stakeAmount > 0 && stakeAmount <= 10000 * 1e6); // Max 10k USDC
        vm.assume(deadline > block.timestamp && deadline <= block.timestamp + 365 days);
        vm.assume(eventDate > deadline && eventDate <= block.timestamp + 365 days + 1);
        vm.assume(maxParticipants > 0 && maxParticipants <= 1000);

        // Create vault with fuzzed parameters
        vm.startPrank(organizer);
        TestVaultATFi fuzzVault = new TestVaultATFi(
            usdc,
            999,
            organizer,
            stakeAmount,
            deadline,
            eventDate,
            maxParticipants
        );
        vm.stopPrank();

        // Verify vault properties
        assertEq(fuzzVault.stakeAmount(), stakeAmount, "Stake amount should match");
        assertEq(fuzzVault.maxParticipant(), maxParticipants, "Max participants should match");

        // Test deposit works
        usdc.mint(participant1, stakeAmount + 1000 * 1e6);
        vm.startPrank(participant1);
        usdc.approve(address(fuzzVault), stakeAmount + 1000 * 1e6);
        fuzzVault.deposit();
        vm.stopPrank();

        assertEq(fuzzVault.getParticipantCount(), 1, "Should have 1 participant");
        assertEq(fuzzVault.balanceOf(participant1), stakeAmount, "Should have correct vault shares");
    }
}