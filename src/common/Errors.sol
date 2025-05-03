// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title Errors
 * @dev Custom errors for the OnGrid Carbon Contracts system.
 */
library Errors {
    // Add custom errors here as they are defined in the contracts
    // Example: error InvalidAmount(uint256 amount);
    // Example: error CallerNotAuthorized();
    error ZeroAddress();
    error InvalidEmissionFactor();
    error BatchAlreadyProcessed();
    error InsufficientFundsForRewards();
    error NoRewardsClaimable();
    error InvalidAmount(uint256 amount);

    // AccessControl Errors (Consider using OZ AccessControlCustomError if preferred)
    error CallerNotMinter();
    error CallerNotDataSubmitter();
    error CallerNotRewardDepositor();
    error CallerNotMetricUpdater();
    error CallerNotNodeManager();
    error CallerNotTreasuryManager();

    // P2P Consensus & Challenge Errors
    error InvalidConsensusConfig();
    error InvalidConsensusProof();
    error InvalidPeerId();
    error NodeNotRegistered();
    error BatchAlreadySubmitted();
    error BatchNotSubmitted();
    error ChallengePeriodNotOver();
    error ChallengePeriodOver();
    error BatchAlreadyChallenged();
    error UnresolvedChallenge();
    error BatchChallengeUpheld();
    error ChallengeNotFound();
    error ChallengeAlreadyResolved();

    // Exchange Errors
    error InvalidExchangeRate();
    error CreditSaleDisabled();
    error InsufficientAllowance();
    error TransferFailed();
    error ExchangeDisabled();
    error InvalidTokenAddress();
}
