// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {CarbonCreditToken} from "../src/token/CarbonCreditToken.sol";
import {EnergyDataBridge} from "../src/bridge/EnergyDataBridge.sol";

/**
 * @title Deployment Script
 * @dev Handles deploying all OnGrid carbon credit contracts in the appropriate order
 */
contract DeployScript is Script {
    // Contract instances
    CarbonCreditToken public creditToken;
    EnergyDataBridge public energyDataBridge;

    // Configuration constant
    uint256 private constant INITIAL_OPERATOR_REWARD_BPS = 8000; // 80%

    function run() external {
        // Pre-flight check
        require(INITIAL_OPERATOR_REWARD_BPS <= 10000, "INVALID_REWARD_BPS");

        // Start broadcasting transactions
        vm.startBroadcast();
        
        // Get the sender address as seen by the script
        address deployer = 0xdB487A73A5b7EF3e773ec115F8C209C12E4EBA37;
        address protocolTreasury = deployer;

        console2.log("Deployer / Admin / Treasury address:", protocolTreasury);

        // 1. Deploy CarbonCreditToken
        console2.log("Deploying CarbonCreditToken...");
        creditToken = new CarbonCreditToken(
            "OnGrid Carbon Credit",  // name
            "OGCC",                  // symbol
            deployer,                // initialAdmin - important: this grants roles to your wallet
            protocolTreasury         // protocolTreasury
        );
        console2.log("CarbonCreditToken deployed at:", address(creditToken));

        // 2. Deploy EnergyDataBridge
        console2.log("Deploying EnergyDataBridge implementation...");
        energyDataBridge = new EnergyDataBridge();
        console2.log("EnergyDataBridge implementation deployed at:", address(energyDataBridge));

        // Initialize EnergyDataBridge
        console2.log("Initializing EnergyDataBridge...");
        energyDataBridge.initialize(
            address(creditToken), // creditToken
            deployer, // initialAdmin
            deployer, // initialSubmitter
            INITIAL_OPERATOR_REWARD_BPS // initialOperatorRewardBps
        );
        console2.log("EnergyDataBridge initialized.");

        // DO NOT attempt to grant roles in this script
        // We'll do that in a separate script

        vm.stopBroadcast();

        // Log successful deployment with addresses to copy for the next step
        console2.log("----- Deployment Complete -----");
        console2.log("Copy these addresses for the SetupRoles script:");
        console2.log("CarbonCreditToken:", address(creditToken));
        console2.log("EnergyDataBridge:", address(energyDataBridge));
    }
} 