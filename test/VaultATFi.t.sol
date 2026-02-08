// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {VaultATFi} from "../src/VaultATFi.sol";
import {FactoryATFi} from "../src/FactoryATFi.sol";
import {ICommitmentVault} from "../src/interfaces/ICommitmentVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

// Mock ERC20
contract MockUSDC is IERC20, IERC20Metadata {
    string public name = "Mock USDC";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return _allowances[owner][spender];
    }
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(
            _allowances[from][msg.sender] >= amount,
            "Insufficient allowance"
        );
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }
}

// Mock ERC4626 for Yield
// Fix: Must implement full IERC20 because IERC4626 inherits it
contract MockYieldVault is IERC4626 {
    IERC20 public _asset;
    mapping(address => uint256) public shareBalances; // Renamed to avoid shadowing
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 public totalShareSupply; // Renamed from totalShares

    constructor(IERC20 assetToken) {
        _asset = assetToken;
    }

    // ERC20 Implementation
    function name() external pure returns (string memory) {
        return "Mock Yield Shares";
    }
    function symbol() external pure returns (string memory) {
        return "mYield";
    }
    function decimals() external pure returns (uint8) {
        return 6;
    }
    function totalSupply() external view returns (uint256) {
        return totalShareSupply;
    }
    function balanceOf(address account) external view returns (uint256) {
        return shareBalances[account];
    }
    function transfer(address to, uint256 amount) external returns (bool) {
        shareBalances[msg.sender] -= amount;
        shareBalances[to] += amount;
        return true;
    }
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return _allowances[owner][spender];
    }
    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        shareBalances[from] -= amount;
        shareBalances[to] += amount;
        return true;
    }

    // ERC4626 Implementation
    function asset() external view returns (address) {
        return address(_asset);
    }
    function totalAssets() external view returns (uint256) {
        return _asset.balanceOf(address(this));
    }
    function convertToShares(uint256 assets) external pure returns (uint256) {
        return assets;
    } // 1:1
    function convertToAssets(
        uint256 shareAmount
    ) external pure returns (uint256) {
        return shareAmount;
    } // 1:1

    function maxDeposit(address) external view returns (uint256) {
        return type(uint256).max;
    }
    function maxMint(address) external view returns (uint256) {
        return type(uint256).max;
    }
    function maxWithdraw(address owner) external view returns (uint256) {
        return shareBalances[owner];
    }
    function maxRedeem(address owner) external view returns (uint256) {
        return shareBalances[owner];
    }

    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    // Fix: Renamed argument 'shares' -> 'shareAmount'
    function previewMint(uint256 shareAmount) external pure returns (uint256) {
        return shareAmount;
    }

    function previewWithdraw(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    // Fix: Renamed argument 'shares' -> 'shareAmount'
    function previewRedeem(
        uint256 shareAmount
    ) external pure returns (uint256) {
        return shareAmount;
    }

    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256) {
        require(
            _asset.transferFrom(msg.sender, address(this), assets),
            "Transfer failed"
        );
        shareBalances[receiver] += assets;
        totalShareSupply += assets;
        return assets;
    }

    function mint(
        uint256 sharesAmount,
        address receiver
    ) external returns (uint256) {
        return this.deposit(sharesAmount, receiver);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256) {
        return this.redeem(assets, receiver, owner);
    }

    function redeem(
        uint256 sharesAmount,
        address receiver,
        address owner
    ) external returns (uint256) {
        require(shareBalances[owner] >= sharesAmount, "Insufficient shares");
        shareBalances[owner] -= sharesAmount;
        totalShareSupply -= sharesAmount;
        require(_asset.transfer(receiver, sharesAmount), "Transfer failed"); // Simulating simple redemption
        return sharesAmount;
    }
}

contract VaultATFiTest is Test {
    FactoryATFi public factory;
    VaultATFi public vault;
    MockUSDC public usdc;
    MockYieldVault public yieldVault;

    address constant TREASURY = 0x6b732552C0E06F69312D7E81969E28179E228C20;

    uint256 constant TEST_STAKE_AMOUNT = 10 * 1e6; // 10 USDC
    uint256 constant MAX_PARTICIPANTS = 50;

    address public owner;
    address public participant1;
    address public participant2;
    address public participant3;
    address public nonParticipant;

    event Staked(address indexed participant, uint256 amount);
    event Verified(address indexed participant);
    event Settled(uint256 totalYield, uint256 protocolFee, uint256 noShowFee);
    event Claimed(address indexed participant, uint256 amount);
    event DepositedToYield(uint256 amount, uint256 shares); // Updated signature
    event StakingOpened();
    event StakingClosed();
    event EventStarted(uint256 totalStaked);

    function setUp() public {
        owner = address(this);
        participant1 = makeAddr("participant1");
        participant2 = makeAddr("participant2");
        participant3 = makeAddr("participant3");
        nonParticipant = makeAddr("nonParticipant");

        usdc = new MockUSDC();
        yieldVault = new MockYieldVault(usdc);

        factory = new FactoryATFi(TREASURY, address(yieldVault), address(usdc));

        // Create vault WITHOUT yield initially for base tests
        uint256 vaultId = factory.createVaultNoYield(
            address(usdc),
            TEST_STAKE_AMOUNT,
            MAX_PARTICIPANTS
        );

        vault = VaultATFi(factory.getVault(vaultId));

        usdc.mint(participant1, 1000 * 1e6);
        usdc.mint(participant2, 1000 * 1e6);
        usdc.mint(participant3, 1000 * 1e6);

        vm.prank(participant1);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(participant2);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(participant3);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ============ Deployment Tests ============

    function testVaultDeployment() public view {
        assertTrue(address(vault) != address(0));
        assertEq(vault.stakeAmount(), TEST_STAKE_AMOUNT);
        assertEq(vault.maxParticipants(), MAX_PARTICIPANTS);
        assertEq(vault.treasury(), TREASURY);
        assertEq(address(vault.assetToken()), address(usdc));
        assertFalse(vault.hasYield());
    }

    // ============ Staking Tests ============

    function testStake() public {
        vm.prank(participant1);
        vm.expectEmit(true, false, false, true);
        emit Staked(participant1, TEST_STAKE_AMOUNT);
        vault.stake();

        assertEq(vault.getParticipantCount(), 1);
        assertEq(
            uint256(vault.getStatus(participant1)),
            uint256(ICommitmentVault.Status.STAKED)
        ); // Fix enum cast
        assertEq(usdc.balanceOf(address(vault)), TEST_STAKE_AMOUNT);
    }

    function testStakeMultipleParticipants() public {
        vm.prank(participant1);
        vault.stake();
        vm.prank(participant2);
        vault.stake();
        vm.prank(participant3);
        vault.stake();

        assertEq(vault.getParticipantCount(), 3);
        assertEq(usdc.balanceOf(address(vault)), TEST_STAKE_AMOUNT * 3);
    }

    function testStakeFailsWhenAlreadyStaked() public {
        vm.prank(participant1);
        vault.stake();

        vm.prank(participant1);
        vm.expectRevert(VaultATFi.AlreadyStaked.selector);
        vault.stake();
    }

    function testStakeFailsWhenStakingClosed() public {
        vault.closeStaking();

        vm.prank(participant1);
        vm.expectRevert(VaultATFi.StakingClosedError.selector);
        vault.stake();
    }

    // ============ Yield Integration Tests ============

    function testDepositToYieldWithYieldVault() public {
        // Create a new vault WITH yield enabled
        uint256 yieldVaultId = factory.createVault(
            address(usdc),
            TEST_STAKE_AMOUNT,
            MAX_PARTICIPANTS
        );
        VaultATFi yVault = VaultATFi(factory.getVault(yieldVaultId));

        // Setup participants for this vault
        vm.prank(participant1);
        usdc.approve(address(yVault), type(uint256).max);
        vm.prank(participant2);
        usdc.approve(address(yVault), type(uint256).max);

        // Stake
        vm.prank(participant1);
        yVault.stake();
        vm.prank(participant2);
        yVault.stake();

        // 20 USDC staked
        uint256 totalStaked = TEST_STAKE_AMOUNT * 2;

        // Mock yields 1:1, so shares = amount
        uint256 expectedShares = totalStaked;

        vm.expectEmit(false, false, false, true);
        emit EventStarted(totalStaked);
        emit DepositedToYield(totalStaked, expectedShares); // Updated event expectation
        yVault.depositToYield();

        assertTrue(yVault.eventStarted());
        assertFalse(yVault.stakingOpen());

        // Check funds moved to yield vault
        assertEq(usdc.balanceOf(address(yieldVault)), totalStaked);
        assertEq(usdc.balanceOf(address(yVault)), 0);

        // Check shares tracking
        // (Mock gives 1:1 shares)
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 shares,
            uint256 deposited
        ) = _getExtendedVaultInfo(yVault);
        assertEq(shares, totalStaked);
        assertEq(deposited, totalStaked);
    }

    function testDepositToYieldWithoutYieldVault() public {
        // Use default vault (no yield)
        vm.prank(participant1);
        vault.stake();

        vault.depositToYield();

        assertTrue(vault.eventStarted());
        // Funds should stay in vault
        assertEq(usdc.balanceOf(address(vault)), TEST_STAKE_AMOUNT);
    }

    // ============ Settlement Tests ============

    function testSettleWithYield() public {
        uint256 yieldVaultId = factory.createVault(
            address(usdc),
            TEST_STAKE_AMOUNT,
            MAX_PARTICIPANTS
        );
        VaultATFi yVault = VaultATFi(factory.getVault(yieldVaultId));

        vm.prank(participant1);
        usdc.approve(address(yVault), type(uint256).max);
        vm.prank(participant1);
        yVault.stake();

        yVault.depositToYield();
        yVault.verify(participant1);

        // Settle
        yVault.settle();

        assertTrue(yVault.settled());
        assertEq(yVault.getClaimable(participant1), TEST_STAKE_AMOUNT);

        // Funds should be back in vault
        assertEq(usdc.balanceOf(address(yVault)), TEST_STAKE_AMOUNT);
        assertEq(usdc.balanceOf(address(yieldVault)), 0);
    }

    // Testing the rounding fix
    function testRoundingErrorFix() public {
        // Create 3 participants
        // Total stake = 30 USDC
        // verified = 3
        // If we simulate loss (Morpho returns 29 USDC)

        uint256 yieldVaultId = factory.createVault(
            address(usdc),
            TEST_STAKE_AMOUNT,
            MAX_PARTICIPANTS
        );
        VaultATFi yVault = VaultATFi(factory.getVault(yieldVaultId));

        // Participant 1 approves and stakes
        vm.startPrank(participant1);
        usdc.approve(address(yVault), type(uint256).max);
        yVault.stake();
        vm.stopPrank();

        // Participant 2 approves and stakes
        vm.startPrank(participant2);
        usdc.approve(address(yVault), type(uint256).max);
        yVault.stake();
        vm.stopPrank();

        // Participant 3 approves and stakes
        vm.startPrank(participant3);
        usdc.approve(address(yVault), type(uint256).max);
        yVault.stake();
        vm.stopPrank();

        yVault.depositToYield(); // 30 USDC sent to yieldVault

        // Simulate loss: yield vault loses 1 USDC
        // Burn 1 USDC from yield vault manually
        vm.prank(address(yieldVault));
        usdc.transfer(address(0xdead), 1 * 1e6); // 1 USDC lost

        yVault.verify(participant1);
        yVault.verify(participant2);
        yVault.verify(participant3);

        yVault.settle();

        // Total returned = 29 USDC
        // Expected distribution: 29 / 3 = 9.666...
        // p1: 9.666666
        // p2: 9.666666
        // p3: 9.666668 (remainder)

        uint256 c1 = yVault.getClaimable(participant1);
        uint256 c2 = yVault.getClaimable(participant2);
        uint256 c3 = yVault.getClaimable(participant3);

        assertEq(c1 + c2 + c3, 29 * 1e6);
        assertTrue(c1 > 0);
        assertTrue(c2 > 0);
        assertTrue(c3 > 0);
    }

    // Attempt to access internal vars via helper
    function _getExtendedVaultInfo(
        VaultATFi _vault
    )
        internal
        view
        returns (
            uint256 totalStaked,
            uint256 verifiedCount,
            uint256 totalYieldEarned,
            uint256 totalProtocolFees,
            bool stakingOpen,
            bool eventStarted,
            bool settled,
            uint256 sharesHeld,
            uint256 depositedAmount
        )
    {
        return (
            _vault.totalStaked(),
            _vault.verifiedCount(),
            _vault.totalYieldEarned(),
            _vault.totalProtocolFees(),
            _vault.stakingOpen(),
            _vault.eventStarted(),
            _vault.settled(),
            _vault.sharesHeld(),
            _vault.depositedAmount()
        );
    }
}
