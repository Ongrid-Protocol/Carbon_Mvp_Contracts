// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IRewardDistributor} from "../interfaces/IRewardDistributor.sol";
import {Errors} from "../common/Errors.sol";

/**
 * @title Reward Distributor
 * @dev Distributes rewards (ERC20 token like USDC) to node operators based on their contribution score.
 * Rewards accrue over time based on a configurable rate per score point.
 * Funds are deposited externally.
 * Contract is pausable and upgradeable (UUPS).
 */
contract RewardDistributor is
    IRewardDistributor,
    ReentrancyGuard,
    Pausable,
    AccessControl,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant REWARD_DEPOSITOR_ROLE = keccak256("REWARD_DEPOSITOR_ROLE");
    bytes32 public constant METRIC_UPDATER_ROLE = keccak256("METRIC_UPDATER_ROLE");

    /**
     * @dev Information stored per node operator.
     * `contributionScore`: The current score representing the operator's contribution.
     * `rewardDebt`: The amount of rewards already accounted for the user, used to calculate pending rewards.
     */
    struct NodeInfo {
        uint256 contributionScore;
        uint256 rewardDebt; // Stores accumulatedRewardsPerScoreUnit * contributionScore at last update
        // `lastUpdateTime` from PRD is implicitly handled by rewardDebt calculation
    }

    IERC20 public immutable rewardToken; // e.g., USDC

    mapping(address => NodeInfo) public nodeInfo; // operatorAddress => Info
    // `rewardsClaimed` from PRD is not needed; we calculate claimable amount on the fly

    uint256 public currentRewardRate; // rewardToken units per contributionScore point per second (scaled)
    uint256 public totalContributionScore;
    uint48 public lastGlobalUpdateTime; // Timestamp of the last global reward update
    uint256 public accumulatedRewardsPerScoreUnit; // Tracks rewards accrued per unit of score over time (scaled)

    // Scaling factor for precision in rate and per-score-unit calculations
    uint256 private constant REWARD_PRECISION = 1e18;

    /**
     * @dev Modifier to check if caller has the METRIC_UPDATER_ROLE.
     */
    modifier onlyMetricUpdater() {
        if (!hasRole(METRIC_UPDATER_ROLE, _msgSender())) revert Errors.CallerNotMetricUpdater();
        _;
    }

    /**
     * @dev Sets up the contract, initializes reward token, and grants roles.
     * @param _rewardToken The address of the ERC20 reward token (e.g., USDC).
     * @param _initialAdmin The address to grant DEFAULT_ADMIN_ROLE, PAUSER_ROLE, and UPGRADER_ROLE.
     */
    constructor(address _rewardToken, address _initialAdmin) {
        if (_rewardToken == address(0)) revert Errors.ZeroAddress();
        if (_initialAdmin == address(0)) revert Errors.ZeroAddress();

        rewardToken = IERC20(_rewardToken);
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(PAUSER_ROLE, _initialAdmin);
        _grantRole(UPGRADER_ROLE, _initialAdmin);
        // REWARD_DEPOSITOR_ROLE and METRIC_UPDATER_ROLE granted separately

        lastGlobalUpdateTime = uint48(block.timestamp);
    }

    /**
     * @dev Sets the rate at which rewards accrue per contribution score point per second.
     * Updates global rewards before changing the rate.
     * Can only be called by the DEFAULT_ADMIN_ROLE.
     * @param _rate The new reward rate (scaled by REWARD_PRECISION).
     */
    function setRewardRate(uint256 _rate)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _updateGlobalRewards(); // Update based on the old rate first
        currentRewardRate = _rate;
        emit RewardRateSet(_rate);
    }

    /**
     * @dev Deposits reward tokens into the contract to fund distribution.
     * Can only be called by the REWARD_DEPOSITOR_ROLE.
     * Requires the contract not to be paused.
     * @param amount The amount of reward tokens to deposit.
     */
    function depositRewards(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyRole(REWARD_DEPOSITOR_ROLE)
    {
        if (amount == 0) revert Errors.InvalidAmount(amount);
        rewardToken.safeTransferFrom(_msgSender(), address(this), amount);
        emit RewardsDeposited(_msgSender(), amount);
    }

    /**
     * @dev Updates the contribution score for a node operator.
     * Can only be called by the METRIC_UPDATER_ROLE.
     * Updates rewards for the specific node before changing their score.
     * @param operator The address of the node operator.
     * @param contributionDelta The *change* in contribution score to be added to the operator's current score.
     * @param timestamp The timestamp associated with this update (must not be in the past relative to last update).
     */
    function updateNodeContribution(address operator, uint256 contributionDelta, uint64 timestamp)
        external
        override
        onlyMetricUpdater
    {
        // We expect the Metric Updater (e.g., Bridge) to provide the delta.

        _updateNodeRewards(operator); // Settle rewards before score change

        NodeInfo storage user = nodeInfo[operator];
        uint256 oldScore = user.contributionScore;
        if (contributionDelta == 0) return; // Nothing to update

        uint256 newContributionScore = oldScore + contributionDelta;
        // Overflow check not strictly needed if score always increases, but good practice
        // require(newContributionScore >= oldScore, \"RewardDistributor: Score overflow\");

        totalContributionScore = totalContributionScore - oldScore + newContributionScore;
        user.contributionScore = newContributionScore;

        // Update reward debt based on the new score for future calculations
        user.rewardDebt = (newContributionScore * accumulatedRewardsPerScoreUnit) / REWARD_PRECISION;

        emit NodeContributionUpdated(operator, newContributionScore, timestamp); // Emit new absolute score
    }

    /**
     * @dev Calculates the amount of rewards claimable by a specific operator.
     * @param operator The address of the node operator.
     * @return pendingRewards The amount of reward tokens claimable.
     */
    function claimableRewards(address operator) public view override returns (uint256) {
        NodeInfo storage user = nodeInfo[operator];
        uint256 currentAccruedPerScoreUnit = accumulatedRewardsPerScoreUnit; // Use value at last global update

        // If total score is > 0, calculate potential rewards accrued since last global update
        if (totalContributionScore > 0 && block.timestamp > lastGlobalUpdateTime) {
            uint256 timeDelta = block.timestamp - lastGlobalUpdateTime;
            uint256 rewardDelta = (timeDelta * currentRewardRate);
            currentAccruedPerScoreUnit += (rewardDelta * REWARD_PRECISION) / totalContributionScore;
        }

        // Calculate total rewards earned = (score * currentAccruedPerScoreUnit / precision) - debt
        uint256 totalEarned = (user.contributionScore * currentAccruedPerScoreUnit) / REWARD_PRECISION;
        uint256 pendingRewards = totalEarned - user.rewardDebt;
        return pendingRewards;
    }

    /**
     * @dev Allows a node operator (msg.sender) to claim their accrued rewards.
     * Requires the contract not to be paused.
     */
    function claimRewards()
        external
        nonReentrant
        whenNotPaused
    {
        address operator = _msgSender();
        _updateNodeRewards(operator); // Settle rewards for the caller

        uint256 pending = claimableRewards(operator); // Recalculate after update
        if (pending == 0) revert Errors.NoRewardsClaimable();

        // Reset reward debt to current state after claiming
        nodeInfo[operator].rewardDebt = (nodeInfo[operator].contributionScore * accumulatedRewardsPerScoreUnit) / REWARD_PRECISION;

        // Check balance before transfer
        uint256 balance = rewardToken.balanceOf(address(this));
        if (pending > balance) {
           // Optional: Revert or only send available balance?
           // Reverting for safety as deposits might be delayed.
           revert Errors.InsufficientFundsForRewards();
        }

        rewardToken.safeTransfer(operator, pending);
        emit RewardsClaimed(operator, pending);
    }

    /**
     * @dev Updates the global reward accumulation state (`accumulatedRewardsPerScoreUnit`).
     * Should be called internally before actions that depend on up-to-date reward values.
     */
    function _updateGlobalRewards() internal virtual {
        if (block.timestamp <= lastGlobalUpdateTime) {
            return; // No time passed or timestamp anomaly
        }
        if (totalContributionScore == 0) {
            lastGlobalUpdateTime = uint48(block.timestamp); // Update time even if no score
            return; // No rewards accrue if no total score
        }

        uint256 timeDelta = block.timestamp - lastGlobalUpdateTime;
        uint256 rewardDelta = (timeDelta * currentRewardRate); // Total reward added in this period
        accumulatedRewardsPerScoreUnit += (rewardDelta * REWARD_PRECISION) / totalContributionScore;
        lastGlobalUpdateTime = uint48(block.timestamp);
    }

    /**
     * @dev Updates the reward state for a specific node operator.
     * Calculates pending rewards and updates their reward debt.
     * Calls `_updateGlobalRewards` first.
     */
    function _updateNodeRewards(address /*operator*/) internal virtual {
        _updateGlobalRewards(); // Ensure global state is current
        // Pending rewards calculation is done in claimableRewards / claimRewards
        // We just need to ensure the global state is updated before calculating
        // or before updating the user's score.
        // Reward debt is updated when score changes or when rewards are claimed.
    }

    /**
     * @dev Pauses reward distribution and claims.
     * Requires the caller to have the PAUSER_ROLE.
     */
    function pause() external virtual onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses reward distribution and claims.
     * Requires the caller to have the PAUSER_ROLE.
     */
    function unpause() external virtual onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Authorizes an upgrade for the UUPS pattern.
     * Requires the caller to have the UPGRADER_ROLE.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}

    // The following functions are overrides required by Solidity.
    // Removed: _update override is not needed for AccessControl/Pausable V5
    // function _update(address from, address to, uint256 value)
    //     internal
    //     override(AccessControl, Pausable) // Adjust if AccessControl requires _update override
    // {
    //     super._update(from, to, value);
    // }

} 