// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ICommitmentVault} from "./interfaces/ICommitmentVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract VaultATFi is ICommitmentVault, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant BPS_PRECISION = 10000;

    // Protocol fees - FIXED at 10%, cannot be changed
    uint256 private immutable NO_SHOW_FEE_BPS = 1000; // 10%
    uint256 private immutable YIELD_FEE_BPS = 1000; // 10%

    // Immutables
    IERC20 public immutable assetToken;
    uint256 public immutable stakeAmount;
    uint256 public immutable maxParticipants;
    uint256 public immutable vaultId;
    address public immutable treasury;
    address public immutable factory;

    // Yield source (optional - address(0) = no yield)
    IERC4626 public immutable yieldVault;

    // Participant data
    struct Participant {
        bool hasStaked;
        bool isVerified;
        bool hasClaimed;
        uint256 claimableAmount;
    }

    mapping(address => Participant) public participants;
    address[] public participantList;

    // Vault state
    bool public stakingOpen;
    bool public eventStarted;
    bool public settled;

    // Tracking
    uint256 public totalStaked;
    uint256 public verifiedCount;
    uint256 public totalYieldEarned;
    uint256 public totalProtocolFees;

    // Yield tracking
    uint256 public sharesHeld;
    uint256 public depositedAmount;

    // Events
    event StakingOpened();
    event StakingClosed();
    event EventStarted(uint256 totalStaked);

    // Errors
    error VaultNotSettled();
    error VaultAlreadySettled();
    error AlreadyStaked();
    error AlreadyVerified();
    error NotStaked();
    error NotVerified();
    error AlreadyClaimed();
    error NothingToClaim();
    error StakingClosedError();
    error EventAlreadyStarted();
    error MaxParticipantsReached();
    error InvalidYieldVault();
    error NoAssetsToDeposit();
    error NoParticipants();
    error InvalidAddress();
    error InvalidStakeAmount();
    error InvalidMaxParticipants();

    constructor(
        uint256 _vaultId,
        address _owner,
        address _factory,
        address _assetToken,
        uint256 _stakeAmount,
        uint256 _maxParticipants,
        address _treasury,
        address _yieldVault
    ) Ownable(_owner) {
        if (_stakeAmount == 0) revert InvalidStakeAmount();
        if (_maxParticipants == 0) revert InvalidMaxParticipants();
        if (_treasury == address(0)) revert InvalidAddress();
        if (_assetToken == address(0)) revert InvalidAddress();

        vaultId = _vaultId;
        factory = _factory;
        assetToken = IERC20(_assetToken);
        stakeAmount = _stakeAmount;
        maxParticipants = _maxParticipants;
        treasury = _treasury;

        // Always set yieldVault (can be address(0) for no-yield mode)
        yieldVault = IERC4626(_yieldVault);

        // Validate yield vault if provided
        if (_yieldVault != address(0)) {
            // Check if yield vault has correct asset
            try IERC4626(_yieldVault).asset() returns (address yieldAsset) {
                if (yieldAsset != _assetToken) revert InvalidYieldVault();
            } catch {
                revert InvalidYieldVault();
            }
        }

        stakingOpen = true;
    }

    // ============ Owner Controls ============

    function openStaking() external onlyOwner {
        if (eventStarted) revert EventAlreadyStarted();
        if (stakingOpen) revert StakingClosedError();
        stakingOpen = true;
        emit StakingOpened();
    }

    function closeStaking() external onlyOwner {
        if (!stakingOpen) revert StakingClosedError();
        stakingOpen = false;
        emit StakingClosed();
    }

    // ============ Participant Functions ============

    function stake() external nonReentrant {
        if (!stakingOpen) revert StakingClosedError();
        if (eventStarted) revert EventAlreadyStarted();
        if (participants[msg.sender].hasStaked) revert AlreadyStaked();

        if (participantList.length >= maxParticipants) revert MaxParticipantsReached();

        assetToken.safeTransferFrom(msg.sender, address(this), stakeAmount);

        participants[msg.sender].hasStaked = true;
        participantList.push(msg.sender);
        totalStaked += stakeAmount;

        emit Staked(msg.sender, stakeAmount);
    }

    function claim() external nonReentrant {
        Participant storage p = participants[msg.sender];

        if (!settled) revert VaultNotSettled();
        if (!p.hasStaked) revert NotStaked();
        if (!p.isVerified) revert NotVerified();
        if (p.hasClaimed) revert AlreadyClaimed();
        if (p.claimableAmount == 0) revert NothingToClaim();

        uint256 amount = p.claimableAmount;
        p.hasClaimed = true;
        p.claimableAmount = 0;

        assetToken.safeTransfer(msg.sender, amount);

        emit Claimed(msg.sender, amount);
    }

    // ============ Owner Functions ============

    function verify(address participant) external onlyOwner {
        _verify(participant);
    }

    function verifyBatch(address[] calldata _participants) external onlyOwner {
        uint256 newlyVerified = 0;

        for (uint256 i = 0; i < _participants.length; i++) {
            address participant = _participants[i];
            Participant storage p = participants[participant];

            if (p.hasStaked && !p.isVerified) {
                p.isVerified = true;
                newlyVerified++;
                emit Verified(participant);
            }
        }

        verifiedCount += newlyVerified;
    }

    function _verify(address participant) internal {
        Participant storage p = participants[participant];
        if (!p.hasStaked) revert NotStaked();
        if (p.isVerified) revert AlreadyVerified();

        p.isVerified = true;
        verifiedCount++;

        emit Verified(participant);
    }

    function depositToYield() external onlyOwner nonReentrant {
        if (eventStarted) revert EventAlreadyStarted();
        if (totalStaked == 0) revert NoAssetsToDeposit();

        stakingOpen = false;
        eventStarted = true;

        if (address(yieldVault) != address(0)) {
            assetToken.forceApprove(address(yieldVault), totalStaked);
            sharesHeld = yieldVault.deposit(totalStaked, address(this));
            depositedAmount = totalStaked;

            emit DepositedToYield(totalStaked, sharesHeld);
        } else {
            emit DepositedToYield(totalStaked, 0);
        }

        emit EventStarted(totalStaked);
    }

    function settle() external onlyOwner nonReentrant {
        if (settled) revert VaultAlreadySettled();
        if (participantList.length == 0) revert NoParticipants();

        stakingOpen = false;

        uint256 totalAssets = totalStaked;
        if (
            eventStarted && address(yieldVault) != address(0) && sharesHeld > 0
        ) {
            // NOTE: We don't revert on loss here to prevent blocking settlement.
            // If yield vault returns less than deposited (e.g. hack/bad debt), we still want users
            // to be able to withdraw whatever is left.

            totalAssets = yieldVault.redeem(
                sharesHeld,
                address(this),
                address(this)
            );
            totalYieldEarned = totalAssets > depositedAmount
                ? totalAssets - depositedAmount
                : 0;
            sharesHeld = 0;
        }

        _calculateAndDistributeRewards(totalAssets);

        settled = true;

        emit Settled(totalYieldEarned, totalProtocolFees, totalProtocolFees);
    }

    function _calculateAndDistributeRewards(uint256 totalAssets) internal {
        uint256 totalParticipants = participantList.length;
        uint256 noShowCount = totalParticipants - verifiedCount;

        uint256 forfeitedStakes = noShowCount * stakeAmount;

        // Safe fee calculation with bounds checking
        uint256 noShowFee = (forfeitedStakes * NO_SHOW_FEE_BPS) / BPS_PRECISION;
        uint256 yieldFee = (totalYieldEarned * YIELD_FEE_BPS) / BPS_PRECISION;

        // Cap total fees to total assets (protects against loss scenarios)
        uint256 totalProtocolFeesCalc = noShowFee + yieldFee;
        totalProtocolFees = totalProtocolFeesCalc > totalAssets
            ? totalAssets
            : totalProtocolFeesCalc;

        uint256 availableForVerified;
        if (totalAssets >= totalProtocolFees) {
            availableForVerified = totalAssets - totalProtocolFees;
        } else {
            // Loss scenario: allocate remaining proportionally
            availableForVerified = 0;
            totalProtocolFees = totalAssets;
        }

        if (verifiedCount > 0 && availableForVerified > 0) {
            uint256 baseAmount = availableForVerified / verifiedCount;
            uint256 remainder = availableForVerified - (baseAmount * verifiedCount);

            uint256 verifiedProcessed = 0;
            for (uint256 i = 0; i < totalParticipants; i++) {
                address participant = participantList[i];
                if (participants[participant].isVerified) {
                    verifiedProcessed++;

                    // Distribute remainder evenly or to last participant
                    if (verifiedProcessed == verifiedCount) {
                        participants[participant].claimableAmount = baseAmount + remainder;
                    } else {
                        participants[participant].claimableAmount = baseAmount;
                    }
                }
            }
        } else if (verifiedCount == 0) {
            // No verified participants - all goes to treasury
            totalProtocolFees = totalAssets;
        }

        if (totalProtocolFees > 0) {
            assetToken.safeTransfer(treasury, totalProtocolFees);
        }
    }

    // ============ View Functions ============

    function getProtocolFees() external view returns (uint256, uint256) {
        return (NO_SHOW_FEE_BPS, YIELD_FEE_BPS);
    }

    function hasYield() external view returns (bool) {
        return address(yieldVault) != address(0);
    }

    function getCurrentBalance() external view returns (uint256) {
        if (address(yieldVault) != address(0) && sharesHeld > 0) {
            return yieldVault.convertToAssets(sharesHeld);
        }
        return assetToken.balanceOf(address(this));
    }

    function getYieldInfo()
        external
        view
        returns (
            bool _hasYield,
            uint256 currentBalance,
            uint256 deposited,
            uint256 estimatedYield
        )
    {
        _hasYield = address(yieldVault) != address(0);

        if (_hasYield && sharesHeld > 0) {
            currentBalance = yieldVault.convertToAssets(sharesHeld);
            deposited = depositedAmount;
            estimatedYield = currentBalance > deposited
                ? currentBalance - deposited
                : 0;
        } else {
            currentBalance = assetToken.balanceOf(address(this));
            deposited = totalStaked;
            estimatedYield = 0;
        }
    }

    function getStatus(address participant) external view returns (Status) {
        Participant storage p = participants[participant];

        if (!p.hasStaked) return Status.NOT_STAKED;
        if (p.hasClaimed) return Status.CLAIMED;
        if (p.isVerified) return Status.VERIFIED;
        return Status.STAKED;
    }

    function getClaimable(address participant) external view returns (uint256) {
        return participants[participant].claimableAmount;
    }

    function getParticipantCount() external view returns (uint256) {
        return participantList.length;
    }

    function getVerifiedCount() external view returns (uint256) {
        return verifiedCount;
    }

    function isStakingClosed() external view returns (bool) {
        return !stakingOpen;
    }

    function isSettled() external view returns (bool) {
        return settled;
    }

    function isEventStarted() external view returns (bool) {
        return eventStarted;
    }

    function getVaultInfo()
        external
        view
        returns (
            address _assetToken,
            uint256 _stakeAmount,
            uint256 _maxParticipants,
            uint256 _currentParticipants,
            bool _stakingOpen,
            bool _eventStarted,
            bool _settled
        )
    {
        return (
            address(assetToken),
            stakeAmount,
            maxParticipants,
            participantList.length,
            stakingOpen,
            eventStarted,
            settled
        );
    }
}
