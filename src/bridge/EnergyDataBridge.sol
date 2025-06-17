// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ICarbonCreditToken} from "../interfaces/ICarbonCreditToken.sol";
import {Errors} from "../common/Errors.sol";

/**
 * @title Energy Data Bridge
 * @dev Receives energy data from trusted off-chain sources (DATA_SUBMITTER_ROLE).
 * Processes data immediately to mint CarbonCreditTokens based on country-specific emission factors.
 * A portion of the minted credits is sent to the node operator as a reward.
 * Pausable and upgradeable (UUPS).
 */
contract EnergyDataBridge is AccessControl, Pausable, ReentrancyGuard, UUPSUpgradeable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant DATA_SUBMITTER_ROLE = keccak256("DATA_SUBMITTER_ROLE");
    bytes32 public constant FACTOR_MANAGER_ROLE = keccak256("FACTOR_MANAGER_ROLE");

    /**
     * @dev Supported countries for emission factor calculation.
     */
    enum Country {
        KENYA,
        NIGERIA,
        SOUTH_AFRICA,
        VIETNAM,
        THAILAND
    }

    /**
     * @dev Represents a single energy data entry within a batch.
     */
    struct EnergyData {
        bytes32 deviceId; // Unique identifier for the energy-generating device
        address nodeOperatorAddress; // Address of the operator responsible for the node/device
        uint256 energyKWh; // Energy produced in kWh (no decimals)
        uint64 timestamp; // Unix timestamp of the data reading or aggregation period end
        Country country; // The country where the energy was generated
        bytes32 verificationHash; // Hash of verification data for this entry
    }

    /**
     * @dev Aggregated statistics for a node operator.
     */
    struct NodeStats {
        uint256 totalEnergyKWh; // Total energy submitted in kWh
        uint256 totalCreditsGenerated; // Total carbon credits generated (in smallest unit, e.g., kg)
    }

    ICarbonCreditToken public carbonCreditToken;

    /**
     * @dev Percentage of minted credits awarded to the node operator, in Basis Points (BPS).
     * 100% = 10000 BPS.
     */
    uint256 public operatorRewardBps;

    /**
     * @dev Emission factors: Grams of CO2e avoided per kWh of energy generated, per country.
     * Scaled by 1e6 for precision (e.g., 500g/kWh stored as 500_000_000).
     */
    mapping(Country => uint256) public countryEmissionFactors; // country enum => grams CO2e * 1e6 / kWh

    // Mapping of node operator addresses to their aggregated stats.
    mapping(address => NodeStats) public nodeStats;

    // Mapping to prevent replay attacks by storing hashes of processed batches
    mapping(bytes32 => bool) public processedBatchHashes;

    /**
     * @dev Emitted when the operator reward BPS is updated.
     */
    event OperatorRewardBpsSet(uint256 oldBps, uint256 newBps);

    /**
     * @dev Emitted when a country's emission factor is updated.
     */
    event CountryEmissionFactorSet(Country indexed country, uint256 oldFactor, uint256 newFactor);

    /**
     * @dev Emitted when a batch of energy data has been successfully processed.
     */
    event EnergyDataProcessed(bytes32 indexed batchHash, uint256 totalCreditsMinted, uint256 entriesProcessed);

    /**
     * @dev Emitted for each entry in a batch, recording an operator's contribution.
     */
    event NodeContributionRecorded(
        address indexed operator,
        uint256 energyKWhContributed,
        uint256 creditsGenerated
    );

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
     * @param _initialAdmin Address to grant DEFAULT_ADMIN_ROLE, PAUSER_ROLE, UPGRADER_ROLE, and FACTOR_MANAGER_ROLE.
     * @param _initialSubmitter Address to grant DATA_SUBMITTER_ROLE.
     * @param _initialOperatorRewardBps The initial percentage of credits for operators (in BPS).
     */
    constructor(
        address _creditToken,
        address _initialAdmin,
        address _initialSubmitter,
        uint256 _initialOperatorRewardBps
    ) {
        if (_creditToken == address(0)) revert Errors.ZeroAddress();
        if (_initialAdmin == address(0)) revert Errors.ZeroAddress();
        if (_initialSubmitter == address(0)) revert Errors.ZeroAddress();
        if (_initialOperatorRewardBps > 10000) revert Errors.InvalidRewardBps();

        carbonCreditToken = ICarbonCreditToken(_creditToken);
        operatorRewardBps = _initialOperatorRewardBps;

        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(PAUSER_ROLE, _initialAdmin);
        _grantRole(UPGRADER_ROLE, _initialAdmin);
        _grantRole(FACTOR_MANAGER_ROLE, _initialAdmin);
        _grantRole(DATA_SUBMITTER_ROLE, _initialSubmitter);

        emit OperatorRewardBpsSet(0, _initialOperatorRewardBps);
    }

    /**
     * @dev Updates the operator reward percentage.
     * Can only be called by the DEFAULT_ADMIN_ROLE.
     * @param _newBps The new reward percentage in Basis Points (BPS). Cannot exceed 10000 (100%).
     */
    function setOperatorRewardBps(uint256 _newBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newBps > 10000) revert Errors.InvalidRewardBps();
        uint256 oldBps = operatorRewardBps;
        operatorRewardBps = _newBps;
        emit OperatorRewardBpsSet(oldBps, _newBps);
    }

    /**
     * @dev Updates the emission factor for a specific country.
     * Can only be called by the FACTOR_MANAGER_ROLE.
     * @param _country The country to update.
     * @param _factor The new emission factor (grams CO2e * 1e6 / kWh). Must be greater than 0.
     */
    function setCountryEmissionFactor(Country _country, uint256 _factor) external onlyRole(FACTOR_MANAGER_ROLE) {
        if (_factor == 0) revert Errors.InvalidEmissionFactor();
        uint256 oldFactor = countryEmissionFactors[_country];
        countryEmissionFactors[_country] = _factor;
        emit CountryEmissionFactorSet(_country, oldFactor, _factor);
    }

    /**
     * @dev Processes a single energy data entry immediately.
     * Mints carbon credits and distributes them between the node operator and the treasury.
     * @param data The EnergyData struct for the single entry.
     */
    function processSingleEnergyData(EnergyData calldata data)
        external
        nonReentrant
        whenNotPaused
        onlyDataSubmitter
    {
        // To leverage batch replay protection, we process this as a single-item batch.
        EnergyData[] memory dataBatch = new EnergyData[](1);
        dataBatch[0] = data;
        processEnergyDataBatch(dataBatch);
    }

    /**
     * @dev Processes a batch of energy data immediately.
     * Mints carbon credits and distributes them between node operators and the treasury.
     * @param dataBatch An array of EnergyData structs.
     */
    function processEnergyDataBatch(EnergyData[] memory dataBatch)
        public
        nonReentrant
        whenNotPaused
        onlyDataSubmitter
    {
        bytes32 batchHash = keccak256(abi.encode(dataBatch));

        if (processedBatchHashes[batchHash]) revert Errors.BatchAlreadyProcessed();

        uint256 batchTotalCreditsMinted = 0;
        uint256 batchTotalTreasuryCredits = 0;
        uint256 numEntries = dataBatch.length;
        uint256 rewardBps = operatorRewardBps;

        for (uint256 i = 0; i < numEntries; ++i) {
            EnergyData memory entry = dataBatch[i];

            // Basic validation
            if (entry.nodeOperatorAddress == address(0) || entry.energyKWh == 0) {
                continue;
            }

            uint256 emissionFactor = countryEmissionFactors[entry.country];
            if (emissionFactor == 0) revert Errors.EmissionFactorNotSetForCountry();

            // Calculate credits: (kWh * (gCO2e * 1e6 / kWh)) / 1e9 = kgCO2e = smallest token unit (3 decimals)
            uint256 creditsToMint = (entry.energyKWh * emissionFactor) / 1e9;
            if (creditsToMint == 0) {
                continue;
            }

            batchTotalCreditsMinted += creditsToMint;

            // Update node operator's lifetime stats
            nodeStats[entry.nodeOperatorAddress].totalEnergyKWh += entry.energyKWh;
            nodeStats[entry.nodeOperatorAddress].totalCreditsGenerated += creditsToMint;
            emit NodeContributionRecorded(entry.nodeOperatorAddress, entry.energyKWh, creditsToMint);

            uint256 operatorShare = (creditsToMint * rewardBps) / 10000;
            if (operatorShare > 0) {
                carbonCreditToken.mint(entry.nodeOperatorAddress, operatorShare);
            }

            batchTotalTreasuryCredits += (creditsToMint - operatorShare);
        }

        if (batchTotalTreasuryCredits > 0) {
            carbonCreditToken.mintToTreasury(batchTotalTreasuryCredits);
        }

        processedBatchHashes[batchHash] = true;

        emit EnergyDataProcessed(batchHash, batchTotalCreditsMinted, numEntries);
    }

    /**
     * @dev Retrieves the aggregated statistics for a given node operator.
     * @param _operator The address of the node operator.
     * @return A NodeStats struct containing the operator's total energy submitted and credits generated.
     */
    function getNodeStats(address _operator) external view returns (NodeStats memory) {
        return nodeStats[_operator];
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
}
