// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VaultATFi} from "./VaultATFi.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FactoryATFi
 * @notice Factory for deploying VaultATFi contracts with multi-token support
 * @dev Creates vaults with embedded yield logic, supports any ERC20 token
 */
contract FactoryATFi is Ownable, Pausable, ReentrancyGuard {
    // ============ Events ============

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

    event AssetTokenRegistered(address indexed token, bool status);

    // ============ State ============

    /// @notice Counter for vault IDs
    uint256 public vaultIdCounter = 1;

    /// @notice Mapping of vault ID to vault address
    mapping(uint256 => address) public vaults;

    /// @notice Mapping to check if address is a vault
    mapping(address => bool) public isVault;

    /// @notice Protocol treasury address (receives all protocol fees)
    address public immutable treasury;

    /// @notice Default Morpho vault address (ERC-4626)
    address public morphoVault;

    /// @notice USDC token address - only token allowed for yield mode
    address public immutable usdcToken;

    // Flexible configuration
    mapping(address => bool) public supportedAssetTokens;

    // ============ Errors ============

    error TokenNotSupported();
    error YieldOnlySupportsUSDC();
    error InvalidTokenAddress();
    error ExceedsMaxParticipants();
    error InvalidStakeAmount();

    // ============ Constructor ============

    constructor(
        address _treasury,
        address _morphoVault,
        address _usdcToken
    ) Ownable(msg.sender) {
        if (_treasury == address(0)) revert InvalidTokenAddress();
        if (_usdcToken == address(0)) revert InvalidTokenAddress();

        treasury = _treasury;
        morphoVault = _morphoVault;
        usdcToken = _usdcToken;
        supportedAssetTokens[_usdcToken] = true;
    }

    // ============ Factory Functions ============

    /// @notice Create a new commitment vault with Morpho yield
    /// @param assetToken Address of ERC20 token to accept
    /// @param stakeAmount Amount each participant must stake (in token decimals)
    /// @param maxParticipants Maximum number of participants
    /// @return vaultId The ID of the created vault
    function createVault(
        address assetToken,
        uint256 stakeAmount,
        uint256 maxParticipants
    ) external whenNotPaused nonReentrant returns (uint256 vaultId) {
        return _createVault(assetToken, stakeAmount, maxParticipants, true);
    }

    /// @notice Create a new commitment vault without yield
    /// @param assetToken Address of ERC20 token to accept
    /// @param stakeAmount Amount each participant must stake (in token decimals)
    /// @param maxParticipants Maximum number of participants
    /// @return vaultId The ID of the created vault
    function createVaultNoYield(
        address assetToken,
        uint256 stakeAmount,
        uint256 maxParticipants
    ) external whenNotPaused nonReentrant returns (uint256 vaultId) {
        return _createVault(assetToken, stakeAmount, maxParticipants, false);
    }

    function _createVault(
        address assetToken,
        uint256 stakeAmount,
        uint256 maxParticipants,
        bool useYield
    ) internal returns (uint256 vaultId) {
        // Validation
        if (assetToken == address(0)) revert InvalidTokenAddress();
        if (!supportedAssetTokens[assetToken]) revert TokenNotSupported();
        if (stakeAmount == 0) revert InvalidStakeAmount();
        if (maxParticipants == 0 || maxParticipants > 10000) revert ExceedsMaxParticipants();

        // Yield mode only supports USDC (Morpho requirement)
        if (useYield && assetToken != usdcToken) revert YieldOnlySupportsUSDC();

        vaultId = vaultIdCounter++;

        // Determine yield contract address (uses morphoVault if yield enabled)
        address yieldVaultAddr = address(0);
        if (useYield && morphoVault != address(0)) {
            yieldVaultAddr = morphoVault;
        }

        // Create the vault - fees are hardcoded constants in VaultATFi
        VaultATFi vault = new VaultATFi(
            vaultId,
            msg.sender, // owner
            address(this), // factory
            assetToken,
            stakeAmount,
            maxParticipants,
            treasury,
            yieldVaultAddr
        );

        vaults[vaultId] = address(vault);
        isVault[address(vault)] = true;

        emit VaultCreated(
            vaultId,
            address(vault),
            msg.sender,
            assetToken,
            stakeAmount,
            maxParticipants,
            yieldVaultAddr,
            block.timestamp
        );
    }

    // ============ Admin Functions ============

    /// @notice Register a new supported asset token
    function registerAssetToken(address token, bool supported) external onlyOwner {
        if (token == address(0)) revert InvalidTokenAddress();
        supportedAssetTokens[token] = supported;
        emit AssetTokenRegistered(token, supported);
    }

    /// @notice Update the default Morpho vault address
    function setMorphoVault(address _morphoVault) external onlyOwner {
        morphoVault = _morphoVault;
    }

    /// @notice Pause vault creation (emergency)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause vault creation
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ View Functions ============

    /// @notice Check if a vault is valid
    function isValidVault(address vault) external view returns (bool) {
        return isVault[vault];
    }

    /// @notice Check if an asset token is supported
    function isTokenSupported(address token) external view returns (bool) {
        return supportedAssetTokens[token];
    }

    /// @notice Get vault address by ID
    function getVault(uint256 vaultId) external view returns (address) {
        return vaults[vaultId];
    }

    /// @notice Get total number of vaults created
    function getVaultCount() external view returns (uint256) {
        return vaultIdCounter - 1;
    }
}
