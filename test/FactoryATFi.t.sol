// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {FactoryATFi} from "../src/FactoryATFi.sol";
import {VaultATFi} from "../src/VaultATFi.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

// Mock ERC20 with configurable decimals
contract MockToken is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

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
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }
}

// Convenience alias for USDC tests
contract MockUSDC is MockToken {
    constructor() MockToken("Mock USDC", "USDC", 6) {}
}

// Minimal Mock ERC4626 for yield vault validation
contract MockYieldVault {
    address public immutable _asset;

    constructor(address assetToken) {
        _asset = assetToken;
    }

    function asset() external view returns (address) {
        return _asset;
    }
}

contract FactoryATFiTest is Test {
    FactoryATFi public factory;
    MockUSDC public usdc;
    MockYieldVault public mockYieldVault;

    address constant TREASURY = 0x6b732552C0E06F69312D7E81969E28179E228C20;

    uint256 constant STAKE_AMOUNT = 10 * 1e6;
    uint256 constant MAX_PARTICIPANTS = 50;

    address public user1;
    address public user2;

    event VaultCreated(
        uint256 indexed vaultId,
        address indexed vault,
        address indexed owner,
        address assetToken,
        uint256 stakeAmount,
        uint256 maxParticipants,
        address yieldVault,
        uint256 timestamp
    );

    function setUp() public {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock USDC
        usdc = new MockUSDC();

        // Deploy mock yield vault that returns USDC as asset
        mockYieldVault = new MockYieldVault(address(usdc));

        // Deploy the factory contract
        factory = new FactoryATFi(TREASURY, address(mockYieldVault), address(usdc));
    }

    // ============ Deployment Tests ============

    function testFactoryDeployment() public view {
        assertEq(factory.treasury(), TREASURY);
        assertEq(factory.usdcToken(), address(usdc));
        assertEq(factory.morphoVault(), address(mockYieldVault));
        assertEq(factory.getVaultCount(), 0);
        assertTrue(factory.isTokenSupported(address(usdc)));
    }

    // ============ Create Vault Tests ============

    function testCreateVaultNoYield() public {
        vm.prank(user1);
        uint256 vaultId = factory.createVaultNoYield(
            address(usdc),
            STAKE_AMOUNT,
            MAX_PARTICIPANTS
        );

        assertEq(vaultId, 1);
        assertEq(factory.getVaultCount(), 1);

        address vaultAddr = factory.getVault(vaultId);
        assertTrue(vaultAddr != address(0));
        assertTrue(factory.isVault(vaultAddr));

        VaultATFi vault = VaultATFi(vaultAddr);
        assertEq(vault.stakeAmount(), STAKE_AMOUNT);
        assertEq(vault.maxParticipants(), MAX_PARTICIPANTS);
        assertEq(vault.owner(), user1);
        // Should have no yield vault
        assertFalse(vault.hasYield());
        assertEq(address(vault.yieldVault()), address(0));
    }

    function testCreateVaultWithYield() public {
        vm.prank(user1);
        uint256 vaultId = factory.createVault(address(usdc), STAKE_AMOUNT, MAX_PARTICIPANTS);

        address vaultAddr = factory.getVault(vaultId);
        VaultATFi vault = VaultATFi(vaultAddr);

        // Should have yield vault set
        assertTrue(vault.hasYield());
        assertEq(address(vault.yieldVault()), address(mockYieldVault));
    }

    function testCreateMultipleVaults() public {
        vm.prank(user1);
        uint256 id1 = factory.createVaultNoYield(
            address(usdc),
            STAKE_AMOUNT,
            MAX_PARTICIPANTS
        );

        vm.prank(user2);
        uint256 id2 = factory.createVaultNoYield(address(usdc), STAKE_AMOUNT * 2, 100);

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(factory.getVaultCount(), 2);

        assertTrue(factory.getVault(id1) != factory.getVault(id2));
    }

    function testCreateVaultEmitsEvent() public {
        vm.prank(user1);
        // Check indexed params (vaultId, skip vault addr, owner) and non-indexed data
        vm.expectEmit(true, false, true, true);
        emit VaultCreated(
            1,
            address(0), // vault address unknown ahead of time
            user1,
            address(usdc),
            STAKE_AMOUNT,
            MAX_PARTICIPANTS,
            address(0),
            block.timestamp
        );
        factory.createVaultNoYield(address(usdc), STAKE_AMOUNT, MAX_PARTICIPANTS);
    }

    function testCreateVaultWithYieldEmitsEvent() public {
        vm.prank(user1);
        // Check indexed params (vaultId, skip vault addr, owner) and non-indexed data
        vm.expectEmit(true, false, true, true);
        emit VaultCreated(
            1,
            address(0), // vault address unknown ahead of time
            user1,
            address(usdc),
            STAKE_AMOUNT,
            MAX_PARTICIPANTS,
            address(mockYieldVault),
            block.timestamp
        );
        factory.createVault(address(usdc), STAKE_AMOUNT, MAX_PARTICIPANTS);
    }

    function testCreateVaultFailsWithZeroStakeAmount() public {
        vm.prank(user1);
        vm.expectRevert(FactoryATFi.InvalidStakeAmount.selector);
        factory.createVaultNoYield(address(usdc), 0, MAX_PARTICIPANTS);
    }

    function testCreateVaultFailsWithZeroMaxParticipants() public {
        vm.prank(user1);
        vm.expectRevert(FactoryATFi.ExceedsMaxParticipants.selector);
        factory.createVaultNoYield(address(usdc), STAKE_AMOUNT, 0);
    }

    // ============ Admin Tests ============

    function testSetMorphoVault() public {
        address newMorpho = address(0x456);
        factory.setMorphoVault(newMorpho);
        assertEq(factory.morphoVault(), newMorpho);
    }

    function testRegisterAssetToken() public {
        MockToken newToken = new MockToken("NewToken", "NEW", 6);
        assertFalse(factory.isTokenSupported(address(newToken)));

        factory.registerAssetToken(address(newToken), true);
        assertTrue(factory.isTokenSupported(address(newToken)));

        factory.registerAssetToken(address(newToken), false);
        assertFalse(factory.isTokenSupported(address(newToken)));
    }

    function testPauseAndUnpause() public {
        // Factory inherits Pausable which has paused() public view
        assertFalse(factory.paused());

        factory.pause();
        assertTrue(factory.paused());

        factory.unpause();
        assertFalse(factory.paused());
    }

    function testCannotCreateVaultWhenPaused() public {
        factory.pause();

        vm.expectRevert();
        factory.createVaultNoYield(address(usdc), STAKE_AMOUNT, MAX_PARTICIPANTS);

        factory.unpause();

        uint256 vaultId = factory.createVaultNoYield(address(usdc), STAKE_AMOUNT, MAX_PARTICIPANTS);
        assertEq(vaultId, 1);
    }

    function testOnlyOwnerCanSetMorphoVault() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.setMorphoVault(address(0x123));
    }

    function testOnlyOwnerCanRegisterTokens() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.registerAssetToken(address(usdc), true);
    }

    function testOnlyOwnerCanPause() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.pause();

        vm.prank(user1);
        vm.expectRevert();
        factory.unpause();
    }

    // ============ USDC-Only Yield Restriction Tests ============

    function testCreateVaultWithYieldFailsForNonUSDC() public {
        // Create IDRX token (2 decimals)
        MockToken idrx = new MockToken("IDRX", "IDRX", 2);
        factory.registerAssetToken(address(idrx), true);

        vm.prank(user1);
        vm.expectRevert(FactoryATFi.YieldOnlySupportsUSDC.selector);
        factory.createVault(address(idrx), 100_00, MAX_PARTICIPANTS); // 100 IDRX
    }

    function testCreateVaultNoYieldWorksWithIDRX() public {
        // Create IDRX token (2 decimals)
        MockToken idrx = new MockToken("IDRX", "IDRX", 2);
        factory.registerAssetToken(address(idrx), true);

        vm.prank(user1);
        uint256 vaultId = factory.createVaultNoYield(
            address(idrx),
            100_00, // 100 IDRX (2 decimals)
            MAX_PARTICIPANTS
        );

        VaultATFi vault = VaultATFi(factory.getVault(vaultId));
        assertEq(address(vault.assetToken()), address(idrx));
        assertFalse(vault.hasYield());
        assertEq(vault.stakeAmount(), 100_00);
    }

    function testCreateVaultNoYieldWorksWithUSDC() public {
        vm.prank(user1);
        uint256 vaultId = factory.createVaultNoYield(
            address(usdc),
            STAKE_AMOUNT,
            MAX_PARTICIPANTS
        );

        VaultATFi vault = VaultATFi(factory.getVault(vaultId));
        assertEq(address(vault.assetToken()), address(usdc));
        assertFalse(vault.hasYield());
    }

    function testCreateVaultFailsWithUnsupportedToken() public {
        MockToken unsupported = new MockToken("Unsupported", "UNS", 18);
        // Don't register it

        vm.prank(user1);
        vm.expectRevert(FactoryATFi.TokenNotSupported.selector);
        factory.createVaultNoYield(address(unsupported), STAKE_AMOUNT, MAX_PARTICIPANTS);
    }
}
