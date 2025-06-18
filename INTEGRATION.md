# OnGrid Protocol: Rust Backend Integration Guide for Data Onboarding

## 1. Overview

This guide provides step-by-step instructions for Rust backend developers to integrate with the OnGrid Protocol, specifically for submitting energy generation data to the blockchain.

### 1.1. Core Focus: Data Onboarding

The primary task for a node's backend is to submit verified energy data to the `EnergyDataBridge` smart contract. This guide focuses exclusively on that process. Upon successful submission, the `EnergyDataBridge` contract automatically mints OnGrid Carbon Credit (OGCC) tokens and distributes them.

### 1.2. Source of Truth

This document is based on the smart contract ABIs. **The ABIs are the ultimate source of truth** for function signatures, data types, event names, and error definitions.

### 1.3. Key Assumptions for Rust Developers

*   **Blockchain Interaction:** You are using a Rust library like `ethers-rs` or `web3-rs`.
*   **Large Numbers:** Contract values of type `uint256` must be handled using a big number library (e.g., `U256` in `ethers-rs`) and represented as **strings in JSON** to avoid precision loss.
*   **Byte Arrays:** Contract values of type `bytes32` are represented as **0x-prefixed hexadecimal strings**.
*   **Addresses:** Ethereum addresses are also 0x-prefixed hex strings.

---

## 2. System Architecture & Prerequisites

The data submission flow is centered around the `EnergyDataBridge` contract. Your backend service acts as a **Data Submitter**.

### 2.1. Required Setup

1.  **Contract ABI:** The JSON ABI for the `EnergyDataBridge` contract.
2.  **Contract Address:** The deployed address of the `EnergyDataBridge` on the target network (e.g., Base Sepolia, Base Mainnet).
3.  **RPC Endpoint:** A connection to a relevant blockchain node.
4.  **Data Submitter Wallet:** Your backend service must control a wallet that has been granted the `DATA_SUBMITTER_ROLE` on the `EnergyDataBridge` contract. **All submission attempts will fail without this role.**

### 2.2. Verifying Your Role

Before attempting to submit data, you can verify your service wallet has the correct permissions by calling the `hasRole` view function on the `EnergyDataBridge` contract:
*   `DATA_SUBMITTER_ROLE()` returns the `bytes32` value for the role.
*   `hasRole(role_hash, your_wallet_address)` returns `true` or `false`.

---

## 3. The Data Onboarding Process: A Step-by-Step Guide

### Step 1: Prepare the Energy Data

All data is submitted using the `EnergyData` struct format. You must construct this object for each data point.

#### The `EnergyData` Struct

| Field                 | Type      | Rust/JSON Type                               | Description                                                                                                                                                                                             |
| --------------------- | --------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `deviceId`            | `bytes32` | Hex String (`"0x..."`)                        | A unique 32-byte identifier for the energy-generating device.                                                                                                                                           |
| `nodeOperatorAddress` | `address` | Hex String (`"0x..."`)                        | The wallet address of the node operator who should receive a share of the minted carbon credits. **Cannot be the zero address.**                                                                      |
| `energyKWh`           | `uint256` | String (`"1500"`)                            | The amount of energy generated in kWh, represented as a `uint256`. Use a string in JSON to preserve precision.                                                                                         |
| `timestamp`           | `uint64`  | Number or String                             | The Unix timestamp (in seconds) when the energy data was recorded.                                                                                                                                      |
| `country`             | `uint8`   | Number                                       | A numeric identifier for the country where the energy was generated. The exact mapping (e.g., `0` for USA) **must be obtained from the OnGrid team.** You can check if a factor is set using `countryEmissionFactors(country_id)`. |
| `verificationHash`    | `bytes32` | Hex String (`"0x..."`)                        | A hash of off-chain data used for verification. To ensure each batch submission is unique (even with identical energy data), this hash should be unique. The exact data to include in this hash **must be specified by the OnGrid team.** |

### Step 2: Submit the Data Transaction

Your service wallet (with `DATA_SUBMITTER_ROLE`) can submit data using one of two functions on the `EnergyDataBridge` contract. Processing is immediate.

#### Option A: Batch Submission (Recommended)
*   **Function:** `processEnergyDataBatch(EnergyData[] calldata dataBatch)`
*   **Input:** An array of `EnergyData` structs.
*   **Use Case:** This is the primary method for submitting multiple data entries efficiently in a single transaction.
*   **Example JSON input for `dataBatch`:**
    ```json
    [
      {
        "deviceId": "0xf22384a22026742475452f1397c231e33c94f55171761a2333abb57552a81f33",
        "nodeOperatorAddress": "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
        "energyKWh": "1500",
        "timestamp": 1678886000,
        "country": 0,
        "verificationHash": "0x5d05267152037081324747517c5950d993910243e18c54e262145b5e3962d334"
      },
      {
        "deviceId": "0x2f8b5a3e74a8d4b3b284e6a8d7c0f2e1a3b5c7d9e8f0a2b4c6d8e0f1a2b3c4d5",
        "nodeOperatorAddress": "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
        "energyKWh": "2500",
        "timestamp": 1678887000,
        "country": 1,
        "verificationHash": "0x8a9f6b2e1d4c3b2a4f6e8d0c2b4a6f8e0d1c2b3a4f5e6d7c8b9a0e1f2d3c4b5a"
      }
    ]
    ```

#### Option B: Single Entry Submission
*   **Function:** `processSingleEnergyData(EnergyData calldata data)`
*   **Input:** A single `EnergyData` struct.
*   **Use Case:** Suitable for submitting individual, high-priority data points.

### Step 3: Monitor the Outcome via Events

After submitting the transaction, you must monitor for its confirmation and listen for events to verify success and gather processing details.

#### Primary Success Event: `EnergyDataProcessed`
This event confirms that your batch was successfully processed.
*   **Event Signature:** `EnergyDataProcessed(bytes32 indexed batchHash, uint256 totalCreditsMinted, uint256 entriesProcessed)`
*   **Payload:**
    *   `batchHash`: The `keccak256` hash of the ABI-encoded `dataBatch` array. **You must calculate this hash on your backend to correlate your submission with this event.**
    *   `totalCreditsMinted`: The total OGCC tokens (in their smallest unit) minted from the entire batch.
    *   `entriesProcessed`: The number of entries from your batch that were successfully processed.

#### Detailed Per-Entry Event: `NodeContributionRecorded`
This event is emitted for *each individual, valid entry* within your batch.
*   **Event Signature:** `NodeContributionRecorded(address indexed operator, uint256 energyKWhContributed, uint256 creditsGenerated)`
*   **Payload:**
    *   `operator`: The node operator who was rewarded for this specific entry.
    *   `energyKWhContributed`: The energy amount from this entry.
    *   `creditsGenerated`: The portion of OGCC credits generated from this entry.

#### Indirect Event: `Transfer` (from the `CarbonCreditToken` contract)
The `EnergyDataBridge` interacts with the `CarbonCreditToken` contract to mint new tokens. This action emits a standard ERC20 `Transfer` event on the token contract.
*   **To Monitor:** First, get the `CarbonCreditToken` address by calling `carbonCreditToken()` on the `EnergyDataBridge`. Then, listen for `Transfer` events on that address.
*   **Mint Signature:** A mint operation appears as a transfer from the zero address: `Transfer(address(0), recipient_address, amount)`. You will see these for both the node operator's reward and the protocol's share.

---

## 4. Handling Errors

If your submission transaction reverts, the processing has failed. The reason is typically included in the transaction receipt. Your backend must be prepared to handle these cases.

### Key Errors to Watch For

| Error                              | Reason & Action                                                                                                                                                                                                                           |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AccessControlUnauthorizedAccount` | Your service wallet does not have the `DATA_SUBMITTER_ROLE`. Contact the protocol admin to have the role granted.                                                                                                                           |
| `BatchAlreadyProcessed`            | A batch with the exact same `keccak256` hash has already been processed. This is a replay protection mechanism. Ensure your `verificationHash` inside each entry is unique for each submission to generate a unique overall `batchHash`. |
| `EmissionFactorNotSetForCountry`   | You have submitted data for a `country` ID that has no emission factor configured. Use the `countryEmissionFactors()` view function to check before submitting.                                                                           |
| `EnforcedPause`                    | The `EnergyDataBridge` contract is currently paused by an administrator. Check the status using the `paused()` view function and wait for it to be unpaused.                                                                               |
| `ZeroAddress`                      | The `nodeOperatorAddress` in one of your `EnergyData` entries was the zero address (`0x00...00`). This is not allowed.                                                                                                                    |
| `InvalidEmissionFactor` / `InvalidRewardBps` | These are admin-related errors you should not encounter during data submission. They occur when an admin tries to set an invalid value. |

---

## 5. Useful View Functions for Monitoring & Verification

Your backend can and should call these `EnergyDataBridge` view functions to get state information before submitting or for displaying data.

*   `carbonCreditToken() returns (address)`: Get the address of the OGCC token contract to monitor `Transfer` events.
*   `countryEmissionFactors(uint8 country) returns (uint256)`: Check the emission factor for a country ID. Returns `0` if not set.
*   `getNodeStats(address _operator) returns (uint256 totalEnergyKWh, uint256 totalCreditsGenerated)`: Get lifetime statistics for a node operator.
*   `operatorRewardBps() returns (uint256)`: Get the current reward share for node operators in Basis Points (e.g., `1500` means 15%).
*   `paused() returns (bool)`: Check if the contract is paused.
*   `processedBatchHashes(bytes32 batchHash) returns (bool)`: A direct way to check if a batch has already been processed.

---

This guide, along with the contract ABIs, should provide a solid foundation for the Rust backend developer. They should always consult the ABIs for exact function signatures, event names, and parameter types.