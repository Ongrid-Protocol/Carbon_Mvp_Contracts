// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICarbonCreditToken} from "../interfaces/ICarbonCreditToken.sol";
import {IRewardDistributor} from "../interfaces/IRewardDistributor.sol";
import {ICarbonCreditExchange} from "../interfaces/ICarbonCreditExchange.sol";
import {Errors} from "../common/Errors.sol";

/**
 * @title Carbon Credit Exchange
 * @dev Handles the exchange of carbon credits for USDC, applying a protocol fee.
 * Connects the credit system to the reward distribution system.
 * Supports both real USDC and mock USDC for testing.
 */
contract CarbonCreditExchange is ICarbonCreditExchange, AccessControl, Pausable, ReentrancyGuard, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant RATE_SETTER_ROLE = keccak256("RATE_SETTER_ROLE");
    bytes32 public constant EXCHANGE_MANAGER_ROLE = keccak256("EXCHANGE_MANAGER_ROLE");
    bytes32 public constant REWARD_DEPOSITOR_ROLE = keccak256("REWARD_DEPOSITOR_ROLE");

    // Protocol configuration
    ICarbonCreditToken public carbonCreditToken;
    IRewardDistributor public rewardDistributor;
    IERC20 public usdcToken;

    // Exchange rate: amount of USDC (in smallest units) per carbon credit token
    // 1 carbon credit = exchangeRate * 1e-6 USDC
    // Example: exchangeRate = 25_000_000 means 1 carbon credit = 25 USDC
    uint256 public exchangeRate;

    // Protocol fee percentage (scaled by 1e6)
    // Example: 150_000 represents a 15% fee
    uint256 public protocolFeePercentage;

    // Percentage of protocol fee that goes to reward distributor (scaled by 1e6)
    // Example: 600_000 represents 60% of the fee
    uint256 public rewardDistributorPercentage;

    // Tracks total exchange volume
    uint256 public totalCreditsExchanged;
    uint256 public totalUsdcCollected;
    uint256 public totalProtocolFees;
    uint256 public totalRewardsFunded;

    // Exchange enabled/disabled flag
    bool public exchangeEnabled;

    /**
     * @dev Sets up the exchange contract with initial parameters.
     * @param _carbonCreditToken The CarbonCreditToken contract address.
     * @param _rewardDistributor The RewardDistributor contract address.
     * @param _usdcToken The USDC token contract address (can be mock for testing).
     * @param _initialAdmin Address to grant admin roles.
     * @param _initialExchangeRate Initial exchange rate (USDC per carbon credit, scaled by 1e6).
     * @param _initialProtocolFee Initial protocol fee percentage (scaled by 1e6).
     * @param _initialRewardDistributorPercentage Initial percentage of fees going to rewards (scaled by 1e6).
     */
    constructor(
        address _carbonCreditToken,
        address _rewardDistributor,
        address _usdcToken,
        address _initialAdmin,
        uint256 _initialExchangeRate,
        uint256 _initialProtocolFee,
        uint256 _initialRewardDistributorPercentage
    ) {
        if (_carbonCreditToken == address(0)) revert Errors.ZeroAddress();
        if (_rewardDistributor == address(0)) revert Errors.ZeroAddress();
        if (_usdcToken == address(0)) revert Errors.ZeroAddress();
        if (_initialAdmin == address(0)) revert Errors.ZeroAddress();
        if (_initialExchangeRate == 0) revert Errors.InvalidExchangeRate();

        // 1e6 = 100%, so ensure the fee is < 1e6 (100%)
        if (_initialProtocolFee >= 1_000_000) revert Errors.InvalidAmount(_initialProtocolFee);

        // Ensure reward percentage is <= 1e6 (100%)
        if (_initialRewardDistributorPercentage > 1_000_000) {
            revert Errors.InvalidAmount(_initialRewardDistributorPercentage);
        }

        carbonCreditToken = ICarbonCreditToken(_carbonCreditToken);
        rewardDistributor = IRewardDistributor(_rewardDistributor);
        usdcToken = IERC20(_usdcToken);
        exchangeRate = _initialExchangeRate;
        protocolFeePercentage = _initialProtocolFee;
        rewardDistributorPercentage = _initialRewardDistributorPercentage;

        // Default to enabled
        exchangeEnabled = true;

        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(PAUSER_ROLE, _initialAdmin);
        _grantRole(UPGRADER_ROLE, _initialAdmin);
        _grantRole(RATE_SETTER_ROLE, _initialAdmin);
        _grantRole(EXCHANGE_MANAGER_ROLE, _initialAdmin);

        emit ExchangeRateSet(0, _initialExchangeRate);
        emit ProtocolFeeSet(0, _initialProtocolFee);
        emit RewardDistributorPercentageSet(0, _initialRewardDistributorPercentage);
        emit USDCTokenSet(_usdcToken);
        emit ExchangeStatusChanged(true);
    }

    /**
     * @dev Sets the exchange rate for carbon credits to USDC.
     * @param _newRate New exchange rate (USDC per carbon credit, scaled by 1e6).
     */
    function setExchangeRate(uint256 _newRate) external onlyRole(RATE_SETTER_ROLE) {
        if (_newRate == 0) revert Errors.InvalidExchangeRate();

        uint256 oldRate = exchangeRate;
        exchangeRate = _newRate;

        emit ExchangeRateSet(oldRate, _newRate);
    }

    /**
     * @dev Sets the protocol fee percentage.
     * @param _newFeePercentage New fee percentage (scaled by 1e6).
     */
    function setProtocolFee(uint256 _newFeePercentage) external onlyRole(EXCHANGE_MANAGER_ROLE) {
        // 1e6 = 100%, so ensure the fee is < 1e6 (100%)
        if (_newFeePercentage >= 1_000_000) revert Errors.InvalidAmount(_newFeePercentage);

        uint256 oldFee = protocolFeePercentage;
        protocolFeePercentage = _newFeePercentage;

        emit ProtocolFeeSet(oldFee, _newFeePercentage);
    }

    /**
     * @dev Sets the percentage of protocol fees that go to the reward distributor.
     * @param _newPercentage New percentage (scaled by 1e6).
     */
    function setRewardDistributorPercentage(uint256 _newPercentage) external onlyRole(EXCHANGE_MANAGER_ROLE) {
        // Ensure percentage is <= 1e6 (100%)
        if (_newPercentage > 1_000_000) revert Errors.InvalidAmount(_newPercentage);

        uint256 oldPercentage = rewardDistributorPercentage;
        rewardDistributorPercentage = _newPercentage;

        emit RewardDistributorPercentageSet(oldPercentage, _newPercentage);
    }

    /**
     * @dev Sets the USDC token address.
     * Useful for switching between real and mock USDC.
     * @param _newUsdcToken New USDC token address.
     */
    function setUSDCToken(address _newUsdcToken) external onlyRole(EXCHANGE_MANAGER_ROLE) {
        if (_newUsdcToken == address(0)) revert Errors.ZeroAddress();
        if (_newUsdcToken == address(usdcToken)) revert Errors.InvalidTokenAddress();

        usdcToken = IERC20(_newUsdcToken);

        emit USDCTokenSet(_newUsdcToken);
    }

    /**
     * @dev Enables or disables the exchange functionality.
     * @param _enabled Whether to enable or disable exchanges.
     */
    function setExchangeEnabled(bool _enabled) external onlyRole(EXCHANGE_MANAGER_ROLE) {
        exchangeEnabled = _enabled;
        emit ExchangeStatusChanged(_enabled);
    }

    /**
     * @dev Allows users to sell carbon credits for USDC.
     * @param creditAmount The amount of carbon credits to sell.
     */
    function exchangeCreditsForUSDC(uint256 creditAmount) external nonReentrant whenNotPaused {
        if (!exchangeEnabled) revert Errors.ExchangeDisabled();
        if (creditAmount == 0) revert Errors.InvalidAmount(creditAmount);

        // Calculate USDC amount (with 6 decimals) based on exchange rate
        // Carbon credits have 3 decimals, USDC has 6 decimals
        // exchangeRate is USDC (smallest units) per carbon credit (smallest units)
        // 1 carbon credit = exchangeRate * 1e-6 USDC
        uint256 usdcAmount = (creditAmount * exchangeRate) / 1e3;

        // Calculate protocol fee
        uint256 feeAmount = (usdcAmount * protocolFeePercentage) / 1_000_000;

        // Calculate net USDC to send to user
        uint256 netUsdcAmount = usdcAmount - feeAmount;

        // Calculate amount for reward distributor
        uint256 rewardAmount = (feeAmount * rewardDistributorPercentage) / 1_000_000;

        // Transfer carbon credits from user to protocol treasury
        carbonCreditToken.transferFromTreasury(msg.sender, creditAmount);

        // Transfer USDC from protocol to user
        if (netUsdcAmount > 0) {
            if (usdcToken.balanceOf(address(this)) < netUsdcAmount) {
                revert Errors.InsufficientFundsForRewards();
            }
            usdcToken.safeTransfer(msg.sender, netUsdcAmount);
        }

        // Fund reward distributor if applicable
        if (rewardAmount > 0) {
            try rewardDistributor.depositRewards(rewardAmount) {
                emit RewardsPoolFunded(rewardAmount);
            } catch {
                // If the call fails (e.g., due to missing role), we silently track it but do not revert
            }
            totalRewardsFunded += rewardAmount;
        }

        // Update stats
        totalCreditsExchanged += creditAmount;
        totalUsdcCollected += usdcAmount;
        totalProtocolFees += feeAmount;

        emit CreditsExchanged(msg.sender, creditAmount, netUsdcAmount, feeAmount);
    }

    /**
     * @dev Pauses the exchange functionality.
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the exchange functionality.
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Authorizes an upgrade for the UUPS pattern.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
