// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewardDistributor {
    /**
     * @dev Emitted when the reward rate is updated.
     */
    event RewardRateSet(uint256 newRate);

    /**
     * @dev Emitted when rewards are deposited into the contract.
     */
    event RewardsDeposited(address indexed depositor, uint256 amount);

    /**
     * @dev Emitted when a node's contribution score is updated.
     */
    event NodeContributionUpdated(address indexed operator, uint256 newScore, uint64 timestamp);

    /**
     * @dev Emitted when an operator claims their rewards.
     */
    event RewardsClaimed(address indexed operator, uint256 amount);

    /**
     * @dev Returns the reward token used by the distributor.
     */
    function rewardToken() external view returns (IERC20);

    /**
     * @dev Updates the contribution metrics for a given node operator.
     * MUST only be callable by the METRIC_UPDATER_ROLE.
     * @param operator The address of the node operator.
     * @param contributionDelta The *change* in contribution score to be added to the operator's current score.
     * @param timestamp The timestamp associated with the contribution update.
     */
    function updateNodeContribution(address operator, uint256 contributionDelta, uint64 timestamp) external;

    /**
     * @dev Returns the amount of rewards claimable by a specific operator.
     * @param operator The address of the node operator.
     * @return The amount of reward tokens claimable.
     */
    function claimableRewards(address operator) external view returns (uint256);
}
