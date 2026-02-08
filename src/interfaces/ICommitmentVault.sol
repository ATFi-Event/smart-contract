// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ICommitmentVault {
    enum Status {
        NOT_STAKED,
        STAKED,
        VERIFIED,
        CLAIMED
    }

    event Staked(address indexed participant, uint256 amount);
    event Verified(address indexed participant);
    event Settled(uint256 totalYield, uint256 protocolFee, uint256 noShowFee);
    event Claimed(address indexed participant, uint256 amount);
    event DepositedToYield(uint256 amount, uint256 shares); // ✅ Updated: Added shares

    function stake() external;
    function claim() external;
    function verify(address participant) external;
    function verifyBatch(address[] calldata participants) external;
    function depositToYield() external;
    function settle() external;

    function getStatus(address participant) external view returns (Status);
    function getClaimable(address participant) external view returns (uint256);
    function getParticipantCount() external view returns (uint256);
    function getVerifiedCount() external view returns (uint256);
    function isStakingClosed() external view returns (bool);
    function isSettled() external view returns (bool);

    // ✅ New View Functions
    function hasYield() external view returns (bool);
    function getCurrentBalance() external view returns (uint256);
    function getYieldInfo()
        external
        view
        returns (
            bool hasYield,
            uint256 currentBalance,
            uint256 deposited,
            uint256 estimatedYield
        );

    function getVaultInfo()
        external
        view
        returns (
            address assetToken,
            uint256 stakeAmount,
            uint256 maxParticipants,
            uint256 currentParticipants,
            bool stakingOpen,
            bool eventStarted,
            bool settled
        );
}
