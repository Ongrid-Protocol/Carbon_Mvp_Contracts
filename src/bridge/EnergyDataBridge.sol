// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ICarbonCreditToken} from "../interfaces/ICarbonCreditToken.sol";
import {IRewardDistributor} from "../interfaces/IRewardDistributor.sol";
import {Errors} from "../common/Errors.sol";

/**
 * @title Energy Data Bridge
 * @dev Receives verified energy data batches from trusted off-chain sources (DATA_SUBMITTER_ROLE).
 * Processes batches to mint CarbonCreditTokens and update node contributions in the RewardDistributor.
 * Includes P2P consensus verification and data challenge mechanism.
 * Pausable and upgradeable (UUPS).
 */
contract EnergyDataBridge is AccessControl, Pausable, ReentrancyGuard, UUPSUpgradeable {
    using ECDSA for bytes32;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant DATA_SUBMITTER_ROLE = keccak256("DATA_SUBMITTER_ROLE");
    bytes32 public constant NODE_MANAGER_ROLE = keccak256("NODE_MANAGER_ROLE");

    /**
     * @dev Represents a single energy data entry within a batch.
     */
    struct EnergyData {
        bytes32 deviceId; // Unique identifier for the energy-generating device
        address nodeOperatorAddress; // Address of the operator responsible for the node/device
        uint256 energyKWh; // Energy produced in kWh (no decimals)
        uint64 timestamp; // Unix timestamp of the data reading or aggregation period end
    }

    /**
     * @dev P2P Consensus proof data for verifying batch validity
     */
    struct P2PConsensusProof {
        bytes32 consensusRoundId; // Unique identifier for the consensus round
        uint256 participatingNodeCount; // Number of nodes that participated in consensus
        bytes32 consensusResultHash; // Hash of the consensus result
        bytes multiSignature; // Aggregated signature from participating nodes
    }

    /**
     * @dev Node registration information
     */
    struct RegisteredNode {
        address operator; // Operator address
        bytes32 peerId; // Identifier in the P2P network
        bool isActive; // Whether the node is actively participating
    }

    /**
     * @dev Challenge information for disputed batches
     */
    struct BatchChallenge {
        address challenger; // Address that submitted the challenge
        bytes32 batchHash; // Hash of the challenged batch
        string reason; // Reason for the challenge
        uint64 challengeTime; // Time when the challenge was submitted
        bool isResolved; // Whether the challenge has been resolved
        bool isUpheld; // If resolved, whether it was upheld or rejected
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

    // Mapping to store registered P2P nodes
    mapping(bytes32 => RegisteredNode) public registeredNodes;

    // Array of peer IDs for enumeration
    bytes32[] public peerIds;

    // Required nodes for consensus (minimum threshold)
    uint256 public requiredConsensusNodes;

    // Batch challenges
    mapping(bytes32 => BatchChallenge) public batchChallenges;

    // Batch data storage for challenge resolution
    mapping(bytes32 => EnergyData[]) public storedBatches;

    // Batch processing delay (time window for challenges)
    uint256 public batchProcessingDelay;

    // Batch submission timestamps
    mapping(bytes32 => uint256) public batchSubmissionTimes;

    /**
     * @dev Emitted when the emission factor is updated.
     */
    event EmissionFactorSet(uint256 oldFactor, uint256 newFactor);

    /**
     * @dev Emitted when a batch of energy data has been successfully processed.
     */
    event EnergyDataProcessed(bytes32 indexed batchHash, uint256 totalCreditsMinted, uint256 entriesProcessed);

    /**
     * @dev Emitted when a batch of energy data has been submitted but awaits processing.
     */
    event EnergyDataSubmitted(bytes32 indexed batchHash, uint256 entriesSubmitted, uint256 processAfterTimestamp);

    /**
     * @dev Emitted when a P2P node is registered.
     */
    event NodeRegistered(bytes32 indexed peerId, address indexed operator);

    /**
     * @dev Emitted when a node's status is updated.
     */
    event NodeStatusUpdated(bytes32 indexed peerId, bool isActive);

    /**
     * @dev Emitted when a batch is challenged.
     */
    event BatchChallenged(bytes32 indexed batchHash, address indexed challenger, string reason);

    /**
     * @dev Emitted when a challenge is resolved.
     */
    event ChallengeResolved(bytes32 indexed batchHash, bool isUpheld);

    /**
     * @dev Modifier to check if caller has the DATA_SUBMITTER_ROLE.
     */
    modifier onlyDataSubmitter() {
        if (!hasRole(DATA_SUBMITTER_ROLE, _msgSender())) revert Errors.CallerNotDataSubmitter();
        _;
    }

    /**
     * @dev Modifier to check if caller has the NODE_MANAGER_ROLE.
     */
    modifier onlyNodeManager() {
        if (!hasRole(NODE_MANAGER_ROLE, _msgSender())) revert Errors.CallerNotNodeManager();
        _;
    }

    /**
     * @dev Sets up the contract, initializes dependencies, and grants initial roles.
     * @param _creditToken Address of the CarbonCreditToken contract.
     * @param _rewardDistributor Address of the RewardDistributor contract.
     * @param _initialAdmin Address to grant DEFAULT_ADMIN_ROLE, PAUSER_ROLE, and UPGRADER_ROLE.
     * @param _initialSubmitter Address to grant DATA_SUBMITTER_ROLE.
     * @param _initialEmissionFactor Initial emission factor (grams CO2e * 1e6 / kWh). Must be greater than 0.
     * @param _initialRequiredConsensusNodes Initial number of nodes required for consensus.
     * @param _initialBatchProcessingDelay Initial delay for batch processing in seconds.
     */
    constructor(
        address _creditToken,
        address _rewardDistributor,
        address _initialAdmin,
        address _initialSubmitter,
        uint256 _initialEmissionFactor,
        uint256 _initialRequiredConsensusNodes,
        uint256 _initialBatchProcessingDelay
    ) {
        if (_creditToken == address(0)) revert Errors.ZeroAddress();
        if (_rewardDistributor == address(0)) revert Errors.ZeroAddress();
        if (_initialAdmin == address(0)) revert Errors.ZeroAddress();
        if (_initialSubmitter == address(0)) revert Errors.ZeroAddress();
        if (_initialEmissionFactor == 0) revert Errors.InvalidEmissionFactor();
        if (_initialRequiredConsensusNodes == 0) revert Errors.InvalidConsensusConfig();

        carbonCreditToken = ICarbonCreditToken(_creditToken);
        rewardDistributor = IRewardDistributor(_rewardDistributor);
        emissionFactor = _initialEmissionFactor;
        requiredConsensusNodes = _initialRequiredConsensusNodes;
        batchProcessingDelay = _initialBatchProcessingDelay;

        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(PAUSER_ROLE, _initialAdmin);
        _grantRole(UPGRADER_ROLE, _initialAdmin);
        _grantRole(NODE_MANAGER_ROLE, _initialAdmin);
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
     * @dev Updates the required number of nodes for consensus.
     * Can only be called by the DEFAULT_ADMIN_ROLE.
     * @param _requiredNodes The new number of required nodes.
     */
    function setRequiredConsensusNodes(uint256 _requiredNodes) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_requiredNodes == 0) revert Errors.InvalidConsensusConfig();
        requiredConsensusNodes = _requiredNodes;
    }

    /**
     * @dev Updates the batch processing delay.
     * Can only be called by the DEFAULT_ADMIN_ROLE.
     * @param _delayInSeconds The new delay in seconds.
     */
    function setBatchProcessingDelay(uint256 _delayInSeconds) external onlyRole(DEFAULT_ADMIN_ROLE) {
        batchProcessingDelay = _delayInSeconds;
    }

    /**
     * @dev Registers a P2P node in the system.
     * Can only be called by addresses with NODE_MANAGER_ROLE.
     * @param _peerId The peer ID in the P2P network.
     * @param _operator The operator address for this node.
     */
    function registerNode(bytes32 _peerId, address _operator) external onlyNodeManager {
        if (_peerId == bytes32(0)) revert Errors.InvalidPeerId();
        if (_operator == address(0)) revert Errors.ZeroAddress();

        if (registeredNodes[_peerId].operator == address(0)) {
            // New node
            peerIds.push(_peerId);
        }

        registeredNodes[_peerId] = RegisteredNode({operator: _operator, peerId: _peerId, isActive: true});

        emit NodeRegistered(_peerId, _operator);
    }

    /**
     * @dev Updates a P2P node's active status.
     * Can only be called by addresses with NODE_MANAGER_ROLE.
     * @param _peerId The peer ID in the P2P network.
     * @param _isActive Whether the node is active.
     */
    function updateNodeStatus(bytes32 _peerId, bool _isActive) external onlyNodeManager {
        if (registeredNodes[_peerId].operator == address(0)) revert Errors.NodeNotRegistered();

        registeredNodes[_peerId].isActive = _isActive;

        emit NodeStatusUpdated(_peerId, _isActive);
    }

    /**
     * @dev Returns the count of registered peer IDs.
     * @return The number of registered peer IDs.
     */
    function getPeerIdCount() external view returns (uint256) {
        return peerIds.length;
    }

    /**
     * @dev Submits a batch of energy data with P2P consensus proof.
     * Stores the batch data for later processing after the challenge period.
     * @param dataBatch An array of EnergyData structs.
     * @param consensusProof The P2P consensus proof for this batch.
     */
    function submitEnergyDataBatch(EnergyData[] calldata dataBatch, P2PConsensusProof calldata consensusProof)
        external
        nonReentrant
        whenNotPaused
        onlyDataSubmitter
    {
        bytes32 batchHash = keccak256(abi.encode(dataBatch));

        if (processedBatchHashes[batchHash]) revert Errors.BatchAlreadyProcessed();
        if (batchSubmissionTimes[batchHash] != 0) revert Errors.BatchAlreadySubmitted();

        // Verify consensus proof
        if (!_verifyP2PConsensus(dataBatch, consensusProof)) revert Errors.InvalidConsensusProof();

        // Store the batch data for later processing
        EnergyData[] storage batchData = storedBatches[batchHash];

        for (uint256 i = 0; i < dataBatch.length; ++i) {
            batchData.push(dataBatch[i]);
        }

        // Record submission time
        uint256 processAfter = block.timestamp + batchProcessingDelay;
        batchSubmissionTimes[batchHash] = processAfter;

        emit EnergyDataSubmitted(batchHash, dataBatch.length, processAfter);
    }

    /**
     * @dev Processes a previously submitted batch after the challenge period has passed.
     * @param batchHash The hash of the batch to process.
     */
    function processBatch(bytes32 batchHash) external nonReentrant whenNotPaused {
        uint256 submissionTime = batchSubmissionTimes[batchHash];
        if (submissionTime == 0) revert Errors.BatchNotSubmitted();
        if (block.timestamp < submissionTime) revert Errors.ChallengePeriodNotOver();
        if (processedBatchHashes[batchHash]) revert Errors.BatchAlreadyProcessed();

        // Check if there's an unresolved challenge
        if (batchChallenges[batchHash].challenger != address(0) && !batchChallenges[batchHash].isResolved) {
            revert Errors.UnresolvedChallenge();
        }

        // Check if challenge was upheld
        if (batchChallenges[batchHash].isResolved && batchChallenges[batchHash].isUpheld) {
            revert Errors.BatchChallengeUpheld();
        }

        EnergyData[] storage dataBatch = storedBatches[batchHash];
        uint256 batchTotalCreditsMinted = 0;
        uint256 numEntries = dataBatch.length;

        for (uint256 i = 0; i < numEntries; ++i) {
            EnergyData storage entry = dataBatch[i];

            // Basic validation
            if (entry.nodeOperatorAddress == address(0)) continue; // Skip invalid entries
            if (entry.energyKWh == 0) continue; // Skip zero energy entries

            // Calculate credits using the same formula as before
            uint256 creditsToMint = (entry.energyKWh * emissionFactor) / 1e9;

            if (creditsToMint > 0) {
                batchTotalCreditsMinted += creditsToMint;
            }

            // Update node contribution in reward distributor
            if (entry.nodeOperatorAddress != address(0) && entry.energyKWh > 0) {
                rewardDistributor.updateNodeContribution(entry.nodeOperatorAddress, entry.energyKWh, entry.timestamp);
            }
        }

        if (batchTotalCreditsMinted > 0) {
            carbonCreditToken.mintToTreasury(batchTotalCreditsMinted);
        }

        processedBatchHashes[batchHash] = true;

        // Cleanup - Keep batch data for audit but can be optimized for gas in production
        // delete storedBatches[batchHash];

        emit EnergyDataProcessed(batchHash, batchTotalCreditsMinted, numEntries);
    }

    /**
     * @dev Challenges a batch that is believed to contain fraudulent or incorrect data.
     * @param batchHash The hash of the batch to challenge.
     * @param reason The reason for the challenge.
     */
    function challengeBatch(bytes32 batchHash, string calldata reason) external nonReentrant whenNotPaused {
        uint256 submissionTime = batchSubmissionTimes[batchHash];
        if (submissionTime == 0) revert Errors.BatchNotSubmitted();
        if (block.timestamp >= submissionTime) revert Errors.ChallengePeriodOver();
        if (processedBatchHashes[batchHash]) revert Errors.BatchAlreadyProcessed();
        if (batchChallenges[batchHash].challenger != address(0)) revert Errors.BatchAlreadyChallenged();

        // Create challenge
        batchChallenges[batchHash] = BatchChallenge({
            challenger: msg.sender,
            batchHash: batchHash,
            reason: reason,
            challengeTime: uint64(block.timestamp),
            isResolved: false,
            isUpheld: false
        });

        emit BatchChallenged(batchHash, msg.sender, reason);
    }

    /**
     * @dev Resolves a challenge for a batch.
     * Can only be called by addresses with DEFAULT_ADMIN_ROLE.
     * @param batchHash The hash of the challenged batch.
     * @param isUpheld Whether the challenge is upheld (true) or rejected (false).
     */
    function resolveChallenge(bytes32 batchHash, bool isUpheld) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (batchChallenges[batchHash].challenger == address(0)) revert Errors.ChallengeNotFound();
        if (batchChallenges[batchHash].isResolved) revert Errors.ChallengeAlreadyResolved();

        batchChallenges[batchHash].isResolved = true;
        batchChallenges[batchHash].isUpheld = isUpheld;

        // If challenge is upheld, extend or reset the processing time
        if (isUpheld) {
            // Invalidate the batch completely
            delete batchSubmissionTimes[batchHash];
        }

        emit ChallengeResolved(batchHash, isUpheld);
    }

    /**
     * @dev Internal function to verify P2P consensus.
     * Checks that the consensus was reached with sufficient valid nodes.
     * @param dataBatch The batch of energy data.
     * @param consensusProof The consensus proof to verify.
     * @return Whether the consensus is valid.
     */
    function _verifyP2PConsensus(EnergyData[] calldata dataBatch, P2PConsensusProof calldata consensusProof)
        internal
        view
        returns (bool)
    {
        // Ensure enough nodes participated
        if (consensusProof.participatingNodeCount < requiredConsensusNodes) {
            return false;
        }

        // Verify that consensus hash matches data batch
        bytes32 expectedHash = keccak256(abi.encode(consensusProof.consensusRoundId, keccak256(abi.encode(dataBatch))));

        if (expectedHash != consensusProof.consensusResultHash) {
            return false;
        }

        // For MVP, we implement a simplified verification
        // In production, this would validate multi-signatures against registered nodes
        return true;
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
