// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {CarbonCreditToken} from "../src/token/CarbonCreditToken.sol";
import {RewardDistributor} from "../src/rewards/RewardDistributor.sol";
import {EnergyDataBridge} from "../src/bridge/EnergyDataBridge.sol";
import {CarbonCreditExchange} from "../src/exchange/CarbonCreditExchange.sol";

/**
 * @title Deployment Script
 * @dev Handles deploying all OnGrid carbon credit contracts in the appropriate order
 */
contract DeployScript is Script {
    // Contract instances
    CarbonCreditToken public creditToken;
    RewardDistributor public rewardDistributor;
    EnergyDataBridge public energyDataBridge;
    CarbonCreditExchange public creditExchange;

    // Configuration constants
    uint256 private constant INITIAL_EMISSION_FACTOR = 500 * 1e6; // 500g CO2e/kWh
    uint256 private constant INITIAL_REQUIRED_CONSENSUS_NODES = 3;
    uint256 private constant INITIAL_BATCH_PROCESSING_DELAY = 24 * 60 * 60; // 24 hours
    
    // Exchange constants
    uint256 private constant INITIAL_EXCHANGE_RATE = 25_000_000; // 25 USDC per credit
    uint256 private constant INITIAL_PROTOCOL_FEE = 150_000; // 15%
    uint256 private constant INITIAL_REWARD_DIST_PERCENTAGE = 600_000; // 60% of fees to rewards

    function run() external {
        // Hardcoded USDC token address for Base Sepolia
        address usdcToken = 0x145aA83e713BBc200aB08172BE9e347442a6c33E;

        // Start broadcasting transactions
        vm.startBroadcast();
        
        // Get the sender address as seen by the script
        address deployer = 0x0a1978f4CeC6AfA754b6Fa11b7D141e529b22741;
        address protocolTreasury = deployer;

        console2.log("Protocol treasury address:", protocolTreasury);
        console2.log("USDC token address:", usdcToken);

        // 1. Deploy CarbonCreditToken
        console2.log("Deploying CarbonCreditToken...");
        creditToken = new CarbonCreditToken(
            "OnGrid Carbon Credit",  // name
            "OGCC",                  // symbol
            deployer,                // initialAdmin - important: this grants roles to your wallet
            protocolTreasury         // protocolTreasury
        );
        console2.log("CarbonCreditToken deployed at:", address(creditToken));

        // 2. Deploy RewardDistributor
        console2.log("Deploying RewardDistributor...");
        rewardDistributor = new RewardDistributor(
            usdcToken,               // rewardToken (USDC)
            deployer                 // initialAdmin
        );
        console2.log("RewardDistributor deployed at:", address(rewardDistributor));

        // 3. Deploy EnergyDataBridge
        console2.log("Deploying EnergyDataBridge...");
        energyDataBridge = new EnergyDataBridge(
            address(creditToken),                // creditToken
            address(rewardDistributor),          // rewardDistributor
            deployer,                            // initialAdmin
            deployer,                            // initialSubmitter
            INITIAL_EMISSION_FACTOR,             // initialEmissionFactor
            INITIAL_REQUIRED_CONSENSUS_NODES,    // initialRequiredConsensusNodes
            INITIAL_BATCH_PROCESSING_DELAY       // initialBatchProcessingDelay
        );
        console2.log("EnergyDataBridge deployed at:", address(energyDataBridge));

        // 4. Deploy CarbonCreditExchange
        console2.log("Deploying CarbonCreditExchange...");
        creditExchange = new CarbonCreditExchange(
            address(creditToken),                // carbonCreditToken
            address(rewardDistributor),          // rewardDistributor
            usdcToken,                           // usdcToken
            deployer,                            // initialAdmin
            INITIAL_EXCHANGE_RATE,               // initialExchangeRate
            INITIAL_PROTOCOL_FEE,                // initialProtocolFee
            INITIAL_REWARD_DIST_PERCENTAGE       // initialRewardDistributorPercentage
        );
        console2.log("CarbonCreditExchange deployed at:", address(creditExchange));

        // DO NOT attempt to grant roles in this script
        // We'll do that in a separate script

        vm.stopBroadcast();

        // Log successful deployment with addresses to copy for the next step
        console2.log("----- Deployment Complete -----");
        console2.log("Copy these addresses for the SetupRoles script:");
        console2.log("CarbonCreditToken:", address(creditToken));
        console2.log("RewardDistributor:", address(rewardDistributor)); 
        console2.log("EnergyDataBridge:", address(energyDataBridge));
        console2.log("CarbonCreditExchange:", address(creditExchange));
    }
} 