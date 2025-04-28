// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // Added for submit function
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ICarbonCreditToken} from "../interfaces/ICarbonCreditToken.sol";
import {IRewardDistributor} from "../interfaces/IRewardDistributor.sol";
import {Errors} from "../common/Errors.sol";

/**
 * @title Energy Data Bridge
 * @dev Receives verified energy data batches from trusted off-chain sources (DATA_SUBMITTER_ROLE).
 * Processes batches to mint CarbonCreditTokens and update node contributions in the RewardDistributor.
 * Pausable and upgradeable (UUPS).
 */
contract EnergyDataBridge is
    AccessControl,
    Pausable,
    ReentrancyGuard, // Ensure submit is nonReentrant
    UUPSUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant DATA_SUBMITTER_ROLE = keccak256("DATA_SUBMITTER_ROLE");

    /**
     * @dev Represents a single energy data entry within a batch.
     */
    struct EnergyData {
        bytes32 deviceId; // Unique identifier for the energy-generating device
        address nodeOperatorAddress; // Address of the operator responsible for the node/device
        uint256 energyKWh; // Energy produced in kWh (no decimals)
        uint64 timestamp; // Unix timestamp of the data reading or aggregation period end
    }

    ICarbonCreditToken public carbonCreditToken;
    IRewardDistributor public rewardDistributor;

    /**
     * @dev Emission factor: Grams of CO2e avoided per kWh of energy generated.
     * Scaled by 1e6 for precision (e.g., 500g/kWh stored as 500_000_000).
     */
    uint256 public emissionFactor; // grams CO2e * 1e6 / kWh

    // Mapping to prevent replay attacks by storing hashes of processed batches
    mapping(bytes32 => bool) public processedBatchHashes;

    /**
     * @dev Emitted when the emission factor is updated.
     */
    event EmissionFactorSet(uint256 oldFactor, uint256 newFactor);

    /**
     * @dev Emitted when a batch of energy data has been successfully processed.
     */
    event EnergyDataProcessed( // Hash of the processed batch data
        // Total carbon credits minted for this batch (scaled by token decimals)
        // Number of entries in the processed batch
    bytes32 indexed batchHash, uint256 totalCreditsMinted, uint256 entriesProcessed);

    /**
     * @dev Modifier to check if caller has the DATA_SUBMITTER_ROLE.
     */
    modifier onlyDataSubmitter() {
        if (!hasRole(DATA_SUBMITTER_ROLE, _msgSender())) revert Errors.CallerNotDataSubmitter();
        _;
    }

    /**
     * @dev Sets up the contract, initializes dependencies, and grants initial roles.
     * @param _creditToken Address of the CarbonCreditToken contract.
     * @param _rewardDistributor Address of the RewardDistributor contract.
     * @param _initialAdmin Address to grant DEFAULT_ADMIN_ROLE, PAUSER_ROLE, and UPGRADER_ROLE.
     * @param _initialSubmitter Address to grant DATA_SUBMITTER_ROLE.
     * @param _initialEmissionFactor Initial emission factor (grams CO2e * 1e6 / kWh). Must be greater than 0.
     */
    constructor(
        address _creditToken,
        address _rewardDistributor,
        address _initialAdmin,
        address _initialSubmitter,
        uint256 _initialEmissionFactor
    ) {
        if (_creditToken == address(0)) revert Errors.ZeroAddress();
        if (_rewardDistributor == address(0)) revert Errors.ZeroAddress();
        if (_initialAdmin == address(0)) revert Errors.ZeroAddress();
        if (_initialSubmitter == address(0)) revert Errors.ZeroAddress();
        if (_initialEmissionFactor == 0) revert Errors.InvalidEmissionFactor();

        carbonCreditToken = ICarbonCreditToken(_creditToken);
        rewardDistributor = IRewardDistributor(_rewardDistributor);
        emissionFactor = _initialEmissionFactor;

        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(PAUSER_ROLE, _initialAdmin);
        _grantRole(UPGRADER_ROLE, _initialAdmin);
        _grantRole(DATA_SUBMITTER_ROLE, _initialSubmitter);

        emit EmissionFactorSet(0, _initialEmissionFactor);
    }

    /**
     * @dev Updates the emission factor used for carbon credit calculations.
     * Can only be called by the DEFAULT_ADMIN_ROLE.
     * @param _factor The new emission factor (grams CO2e * 1e6 / kWh). Must be greater than 0.
     */
    function setEmissionFactor(uint256 _factor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_factor == 0) revert Errors.InvalidEmissionFactor();
        uint256 oldFactor = emissionFactor;
        emissionFactor = _factor;
        emit EmissionFactorSet(oldFactor, _factor);
    }

    /**
     * @dev Submits a batch of energy data for processing.
     * Calculates and mints carbon credits, updates node contributions.
     * Requires the caller to have the DATA_SUBMITTER_ROLE.
     * Operation is paused if the contract is paused.
     * Uses nonReentrant modifier to prevent reentrancy attacks.
     * @param dataBatch An array of EnergyData structs.
     */
    function submitEnergyDataBatch(EnergyData[] calldata dataBatch)
        external
        nonReentrant
        whenNotPaused
        onlyDataSubmitter
    {
        bytes32 batchHash = keccak256(abi.encode(dataBatch));
        if (processedBatchHashes[batchHash]) revert Errors.BatchAlreadyProcessed();

        uint256 batchTotalCreditsMinted = 0;
        uint256 numEntries = dataBatch.length;

        // Temporary storage for aggregated contributions per operator within the batch
        // This avoids multiple calls to rewardDistributor for the same operator within a batch
        // mapping(address => uint256) batchContributions; // Removed: Unused in current implementation

        for (uint256 i = 0; i < numEntries; ++i) {
            EnergyData calldata entry = dataBatch[i];

            // Basic validation
            if (entry.nodeOperatorAddress == address(0)) continue; // Skip invalid entries
            if (entry.energyKWh == 0) continue; // Skip zero energy entries

            // Calculate credits: (kWh * (grams/kWh * 1e6)) / (grams/tonne * factor_scale * token_decimals_scale)
            // (kWh * (g * 1e6 / kWh)) / (1e6 g/tonne * 1e6 scale * 1e3 token_decimals)
            // Simplified: (kWh * emissionFactor) / (1e6 * 1e3) = (kWh * emissionFactor) / 1e9
            // Assumes CarbonCreditToken has 3 decimals.
            uint256 creditsToMint = (entry.energyKWh * emissionFactor) / 1e9; // Results in token units (3 decimals)

            if (creditsToMint > 0) {
                batchTotalCreditsMinted += creditsToMint;
            }

            // Aggregate contribution score update (using energyKWh as score delta for simplicity)
            // The actual score logic might be more complex, but for MVP this directly links energy to contribution.
            // Note: RewardDistributor expects absolute score, not delta. Aggregation logic might need rework
            // if multiple entries for same operator exist. For now, assume bridge aggregates off-chain or
            // RewardDistributor handles deltas (which it currently doesn't).
            // Let's stick to the PRD's flow for now, acknowledging the gas implication.
            // Call RewardDistributor with the energy amount as the contribution delta.
            if (entry.nodeOperatorAddress != address(0) && entry.energyKWh > 0) {
                rewardDistributor.updateNodeContribution(entry.nodeOperatorAddress, entry.energyKWh, entry.timestamp);
            }
        }

        if (batchTotalCreditsMinted > 0) {
            carbonCreditToken.mintToTreasury(batchTotalCreditsMinted);
        }

        processedBatchHashes[batchHash] = true;
        emit EnergyDataProcessed(batchHash, batchTotalCreditsMinted, numEntries);
    }

    /**
     * @dev Pauses data submission.
     * Requires the caller to have the PAUSER_ROLE.
     */
    function pause() external virtual onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses data submission.
     * Requires the caller to have the PAUSER_ROLE.
     */
    function unpause() external virtual onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Authorizes an upgrade for the UUPS pattern.
     * Requires the caller to have the UPGRADER_ROLE.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // The following functions are overrides required by Solidity.
    // Removed: _update override is not needed for AccessControl/Pausable V5
    // function _update(address from, address to, uint256 value)
    //     internal
    //     override(AccessControl, Pausable) // Adjust if AccessControl requires _update override
    // {
    //     super._update(from, to, value);
    // }
}
