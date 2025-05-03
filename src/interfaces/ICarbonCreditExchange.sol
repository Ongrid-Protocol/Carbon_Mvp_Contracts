// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICarbonCreditToken} from "./ICarbonCreditToken.sol";
import {IRewardDistributor} from "./IRewardDistributor.sol";

/**
 * @title Carbon Credit Exchange Interface
 * @dev Interface for the CarbonCreditExchange contract.
 */
interface ICarbonCreditExchange {
    /**
     * @dev Emitted when the exchange rate is updated.
     */
    event ExchangeRateSet(uint256 oldRate, uint256 newRate);

    /**
     * @dev Emitted when the protocol fee percentage is updated.
     */
    event ProtocolFeeSet(uint256 oldFee, uint256 newFee);

    /**
     * @dev Emitted when the reward distributor percentage is updated.
     */
    event RewardDistributorPercentageSet(uint256 oldPercentage, uint256 newPercentage);

    /**
     * @dev Emitted when the USDC token address is updated.
     */
    event USDCTokenSet(address indexed tokenAddress);

    /**
     * @dev Emitted when the exchange enabled status is updated.
     */
    event ExchangeStatusChanged(bool enabled);

    /**
     * @dev Emitted when credits are exchanged for USDC.
     */
    event CreditsExchanged(address indexed user, uint256 creditAmount, uint256 usdcAmount, uint256 feeAmount);

    /**
     * @dev Emitted when the rewards pool is funded.
     */
    event RewardsPoolFunded(uint256 amount);

    /**
     * @dev Returns the CarbonCreditToken contract address.
     */
    function carbonCreditToken() external view returns (ICarbonCreditToken);

    /**
     * @dev Returns the RewardDistributor contract address.
     */
    function rewardDistributor() external view returns (IRewardDistributor);

    /**
     * @dev Returns the USDC token contract address.
     */
    function usdcToken() external view returns (IERC20);

    /**
     * @dev Returns the current exchange rate.
     */
    function exchangeRate() external view returns (uint256);

    /**
     * @dev Returns the current protocol fee percentage.
     */
    function protocolFeePercentage() external view returns (uint256);

    /**
     * @dev Returns the percentage of protocol fees going to the reward distributor.
     */
    function rewardDistributorPercentage() external view returns (uint256);

    /**
     * @dev Returns whether the exchange is currently enabled.
     */
    function exchangeEnabled() external view returns (bool);

    /**
     * @dev Returns various statistics about the exchange.
     */
    function totalCreditsExchanged() external view returns (uint256);
    function totalUsdcCollected() external view returns (uint256);
    function totalProtocolFees() external view returns (uint256);
    function totalRewardsFunded() external view returns (uint256);

    /**
     * @dev Exchanges carbon credits for USDC.
     * @param creditAmount The amount of carbon credits to exchange.
     */
    function exchangeCreditsForUSDC(uint256 creditAmount) external;

    /**
     * @dev Sets the exchange rate.
     * @param newRate The new exchange rate.
     */
    function setExchangeRate(uint256 newRate) external;

    /**
     * @dev Sets the protocol fee percentage.
     * @param newFeePercentage The new fee percentage.
     */
    function setProtocolFee(uint256 newFeePercentage) external;

    /**
     * @dev Sets the reward distributor percentage.
     * @param newPercentage The new percentage.
     */
    function setRewardDistributorPercentage(uint256 newPercentage) external;

    /**
     * @dev Sets the USDC token address.
     * @param newUsdcToken The new USDC token address.
     */
    function setUSDCToken(address newUsdcToken) external;

    /**
     * @dev Enables or disables the exchange functionality.
     * @param enabled Whether to enable or disable the exchange.
     */
    function setExchangeEnabled(bool enabled) external;
}
