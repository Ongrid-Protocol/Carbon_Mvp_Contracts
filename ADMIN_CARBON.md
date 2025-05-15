# OnGrid Protocol: Admin Integration and Testing Guide

This guide outlines the necessary administrative setup, inter-contract role assignments for full system functionality, and a strategy for testing the integrated OnGrid Protocol smart contracts.

## Table of Contents

1.  [Prerequisites](#prerequisites)
2.  [Part 1: Critical Inter-Contract Role Assignments](#part-1-critical-inter-contract-role-assignments)
    *   [1.1 Grant `MINTER_ROLE` to `EnergyDataBridge` on `CarbonCreditToken`](#11-grant-minter_role-to-energydatabridge-on-carboncredittoken)
    *   [1.2 Grant `METRIC_UPDATER_ROLE` to `EnergyDataBridge` on `RewardDistributor`](#12-grant-metric_updater_role-to-energydatabridge-on-rewarddistributor)
    *   [1.3 Grant `REWARD_DEPOSITOR_ROLE` to `CarbonCreditExchange` on `RewardDistributor`](#13-grant-reward_depositor_role-to-carboncreditexchange-on-rewarddistributor)
3.  [Part 2: Administrative Wallet & Panel Integration Setup](#part-2-administrative-wallet--panel-integration-setup)
    *   [2.1 Designate an "Admin Wallet"](#21-designate-an-admin-wallet)
    *   [2.2 Grant Administrative Roles to `adminWalletAddress`](#22-grant-administrative-roles-to-adminwalletaddress)
    *   [2.3 Admin Panel Integration - Interacting with Contracts](#23-admin-panel-integration---interacting-with-contracts)
4.  [Part 3: Full Functionality Considerations Checklist](#part-3-full-functionality-considerations-checklist)
5.  [Part 4: Testing Strategy for Contracts and Functionality](#part-4-testing-strategy-for-contracts-and-functionality)
    *   [5.1 Smart Contract Unit Testing](#51-smart-contract-unit-testing)
    *   [5.2 Smart Contract Integration Testing](#52-smart-contract-integration-testing)
    *   [5.3 Backend Integration Testing (e.g., Rust Service)](#53-backend-integration-testing-eg-rust-service)
    *   [5.4 End-to-End (E2E) Scenario Testing](#54-end-to-end-e2e-scenario-testing)
    *   [5.5 Role-Based Access Control (RBAC) Testing](#55-role-based-access-control-rbac-testing)
    *   [5.6 Edge Case and Failure Mode Testing](#56-edge-case-and-failure-mode-testing)
    *   [5.7 Security-Specific Testing](#57-security-specific-testing)
    *   [5.8 Testing Environments](#58-testing-environments)
    *   [5.9 Recommended Tooling](#59-recommended-tooling)

---

## Prerequisites

1.  **Contracts Deployed:** All smart contracts (`CarbonCreditToken`, `RewardDistributor`, `EnergyDataBridge`, `CarbonCreditExchange`) are deployed, and their addresses are known.
2.  **Deployer Account Access:** You have access to the `deployer` wallet (e.g., `0x0a1978f4CeC6AfA754b6Fa11b7D141e529b22741` as per `Deploy.s.sol`) to sign transactions.
3.  **Contract ABIs:** Available for interacting with the contracts (e.g., via `ethers.js`, `web3.py`, `cast`, or your Rust setup).
4.  **Role Hashes:** You'll need the `bytes32` hash for each role string. These are defined as public constants in the contracts and can be queried, or calculated as `keccak256("ROLE_STRING")`.
    *   `MINTER_ROLE = keccak256("MINTER_ROLE")`
    *   `METRIC_UPDATER_ROLE = keccak256("METRIC_UPDATER_ROLE")`
    *   `REWARD_DEPOSITOR_ROLE = keccak256("REWARD_DEPOSITOR_ROLE")`
    *   Other admin roles: `PAUSER_ROLE`, `UPGRADER_ROLE`, `NODE_MANAGER_ROLE`, `RATE_SETTER_ROLE`, `EXCHANGE_MANAGER_ROLE`, `TREASURY_MANAGER_ROLE`, `DEFAULT_ADMIN_ROLE`.

---

## Part 1: Critical Inter-Contract Role Assignments

The `deployer` account, holding `DEFAULT_ADMIN_ROLE` on all contracts, must grant specific roles to the *contract addresses themselves* to enable core system functionalities.

**Let:**
*   `carbonCreditTokenAddress` be the address of your deployed `CarbonCreditToken`.
*   `rewardDistributorAddress` be the address of your deployed `RewardDistributor`.
*   `energyDataBridgeAddress` be the address of your deployed `EnergyDataBridge`.
*   `carbonCreditExchangeAddress` be the address of your deployed `CarbonCreditExchange`.

### 1.1 Grant `MINTER_ROLE` to `EnergyDataBridge` on `CarbonCreditToken`

*   **Purpose:** To allow the `EnergyDataBridge` contract to mint new OGCC tokens to the treasury when processing valid energy data batches.
*   **Action:** The `deployer` calls `grantRole` on the `CarbonCreditToken` contract.
*   **Transaction Details:**
    *   **From:** `deployer` address
    *   **To:** `carbonCreditTokenAddress`
    *   **Function:** `grantRole(bytes32 role, address account)`
    *   **Parameters:**
        *   `role`: `MINTER_ROLE` (as `bytes32`) on `CarbonCreditToken`. (e.g., `0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6`)
        *   `account`: `energyDataBridgeAddress`.
*   **Why:** `EnergyDataBridge.processBatch()` calls `carbonCreditToken.mintToTreasury()`, protected by `onlyMinter`.

### 1.2 Grant `METRIC_UPDATER_ROLE` to `EnergyDataBridge` on `RewardDistributor`

*   **Purpose:** To allow the `EnergyDataBridge` contract to update node contribution scores in the `RewardDistributor`.
*   **Action:** The `deployer` calls `grantRole` on the `RewardDistributor` contract.
*   **Transaction Details:**
    *   **From:** `deployer` address
    *   **To:** `rewardDistributorAddress`
    *   **Function:** `grantRole(bytes32 role, address account)`
    *   **Parameters:**
        *   `role`: `METRIC_UPDATER_ROLE` (as `bytes32`) on `RewardDistributor`. (e.g., `0x199886700135612483117405020107d9a2807208850a995c30ef73476df9ac45`)
        *   `account`: `energyDataBridgeAddress`.
*   **Why:** `EnergyDataBridge.processBatch()` calls `rewardDistributor.updateNodeContribution()`, protected by `onlyMetricUpdater`.

### 1.3 Grant `REWARD_DEPOSITOR_ROLE` to `CarbonCreditExchange` on `RewardDistributor`

*   **Purpose:** To allow `CarbonCreditExchange` to deposit a portion of protocol fees (USDC) into `RewardDistributor`.
*   **Action:** The `deployer` calls `grantRole` on the `RewardDistributor` contract.
*   **Transaction Details:**
    *   **From:** `deployer` address
    *   **To:** `rewardDistributorAddress`
    *   **Function:** `grantRole(bytes32 role, address account)`
    *   **Parameters:**
        *   `role`: `REWARD_DEPOSITOR_ROLE` (as `bytes32`) on `RewardDistributor`. (e.g., `0x1b25299172796740cf099512e9807657088868995050680f5063940689553178`)
        *   `account`: `carbonCreditExchangeAddress`.
*   **Why:** `CarbonCreditExchange.exchangeCreditsForUSDC()` calls `rewardDistributor.depositRewards()`, protected by `onlyRole(REWARD_DEPOSITOR_ROLE)`.
*   **Operational Note:** For `depositRewards` to succeed, `CarbonCreditExchange` (as `msg.sender`) must also *approve* `RewardDistributor` to spend its USDC. This ERC20 allowance is separate from the role.

---

## Part 2: Administrative Wallet & Panel Integration Setup

For ongoing management, use an admin panel interacting via a dedicated "Admin Wallet".

### 2.1 Designate an "Admin Wallet"

*   Choose/create a secure Ethereum address (`adminWalletAddress`) for administrative transactions. This could be an EOA or a multisig.

### 2.2 Grant Administrative Roles to `adminWalletAddress`

The `deployer` grants necessary roles to `adminWalletAddress`.

*   **Option A: Grant `DEFAULT_ADMIN_ROLE` (Broad Access)**
    *   The `deployer` grants `DEFAULT_ADMIN_ROLE` (hash: `0x0000000000000000000000000000000000000000000000000000000000000000`) on each contract to `adminWalletAddress`.
    *   Example for `CarbonCreditToken`: Call `grantRole(DEFAULT_ADMIN_ROLE, adminWalletAddress)` on `carbonCreditTokenAddress`. Repeat for all contracts.

*   **Option B: Grant Specific Managerial Roles (Granular Access)**
    *   Grant only necessary operational admin roles. Examples:
        *   **`CarbonCreditToken`:** `TREASURY_MANAGER_ROLE`, `PAUSER_ROLE`.
        *   **`RewardDistributor`:** `PAUSER_ROLE`; `DEFAULT_ADMIN_ROLE` (or specific role) for `setRewardRate`.
        *   **`EnergyDataBridge`:** `NODE_MANAGER_ROLE`, `PAUSER_ROLE`; `DEFAULT_ADMIN_ROLE` for parameters/challenges; `DATA_SUBMITTER_ROLE` if applicable.
        *   **`CarbonCreditExchange`:** `RATE_SETTER_ROLE`, `EXCHANGE_MANAGER_ROLE`, `PAUSER_ROLE`.
    *   Use `grantRole(SPECIFIC_ROLE_HASH, adminWalletAddress)` on the respective contract.

### 2.3 Admin Panel Integration - Interacting with Contracts

Once `adminWalletAddress` has roles, your admin panel can initiate transactions signed by it. Refer to `INTEGRATION.md` (section "Admin Panel Integration") for function details.

**Key Administrative Functions:**
*   **System Parameters:** `setEmissionFactor`, `setRequiredConsensusNodes`, `setBatchProcessingDelay`, `setRewardRate`, `setExchangeRate`, `setProtocolFee`, etc.
*   **Operational Control:** `pause()`/`unpause()`, `setExchangeEnabled(bool)`.
*   **User/Node Management (`EnergyDataBridge`):** `registerNode`, `updateNodeStatus`, `resolveChallenge`.
*   **Treasury Management (`CarbonCreditToken`):** `setProtocolTreasury`, `transferFromTreasury`, `retireFromTreasury`.
*   **Role Management (All Contracts):** `grantRole`, `revokeRole`.

**Monitoring:** The admin panel should monitor events like `RoleGranted`, `RoleRevoked`, `Paused`, `Unpaused`, and parameter change events (`EmissionFactorSet`, etc.) for logging/auditing.

---

## Part 3: Full Functionality Considerations Checklist

1.  **Inter-Contract Roles Assigned (Part 1):** Verify all critical roles are set.
2.  **Admin Wallet Roles Assigned (Part 2):** Ensure `adminWalletAddress` has sufficient privileges.
3.  **Data Submitter Setup (`EnergyDataBridge`):** An address/service needs `DATA_SUBMITTER_ROLE` on `EnergyDataBridge`.
4.  **USDC Liquidity and Allowances (`CarbonCreditExchange`):**
    *   `CarbonCreditExchange` contract must be funded with USDC.
    *   `CarbonCreditExchange` must *approve* `RewardDistributor` to spend its USDC for reward deposits.
5.  **P2P Consensus Mechanism (`EnergyDataBridge`):** The `_verifyP2PConsensus` placeholder needs full implementation.
6.  **Node Operator Wallets (`RewardDistributor`):** Operators need wallets for `claimRewards()`.
7.  **User Wallets (`CarbonCreditExchange` & `CarbonCreditToken`):** Users need wallets for OGCC, `approve`, and `exchangeCreditsForUSDC`.

---

## Part 4: Testing Strategy for Contracts and Functionality

A multi-layered testing approach is crucial to ensure correctness, security, and reliability.

### 5.1 Smart Contract Unit Testing

*   **Focus:** Individual functions within each contract in isolation.
*   **Method:** Use Foundry's `forge test`. Write tests in Solidity.
*   **Coverage:**
    *   Test all public and external functions.
    *   Verify correct state changes.
    *   Check event emissions with correct parameters.
    *   Test modifiers and access control (e.g., `onlyRole` reverts).
    *   Validate input validation and error handling (custom errors).
    *   Test mathematical calculations for precision and overflow/underflow.

### 5.2 Smart Contract Integration Testing

*   **Focus:** Interactions between deployed contract instances.
*   **Method:** Use Foundry's `forge test` by deploying multiple contracts within a test setup, or `forge script` for more complex scenarios.
*   **Coverage:**
    *   Test the full lifecycle: data submission (`EnergyDataBridge`) -> credit minting (`CarbonCreditToken`) -> reward score update (`RewardDistributor`).
    *   Test exchange flow: user OGCC sale (`CarbonCreditExchange`) -> USDC transfer -> fee distribution -> reward pool funding (`RewardDistributor`).
    *   Verify role assignments enable intended cross-contract calls.
    *   Test scenarios involving challenges and resolutions in `EnergyDataBridge`.

### 5.3 Backend Integration Testing (e.g., Rust Service)

*   **Focus:** Ensuring the backend service (e.g., Rust application) correctly interacts with the deployed smart contracts.
*   **Method:** Write integration tests within the backend's test suite.
*   **Coverage:**
    *   **Connection & Instantiation:** Verify successful connection to the blockchain and instantiation of contract clients using ABIs and addresses.
    *   **Parameter Encoding/Decoding:** Ensure correct handling of types like `uint256` (big numbers), `address`, `bytes32`, `bytes`, arrays, and structs when calling contract functions and interpreting results/events.
    *   **View Functions:** Test calls to all relevant view functions and validate returned data against expected values.
    *   **State-Changing Functions:**
        *   Test sending transactions for critical operations (e.g., `submitEnergyDataBatch`, admin functions).
        *   Ensure transactions are signed by the correct wallet (admin wallet, data submitter wallet).
        *   Verify handling of transaction receipts (success, failure, gas usage).
        *   Test error handling for reverts from contracts (e.g., insufficient permissions, invalid state).
    *   **Event Listening & Processing:**
        *   Verify the backend can subscribe to and correctly parse all relevant contract events.
        *   Test the backend's logic for reacting to these events (e.g., updating its internal state, triggering other processes).

### 5.4 End-to-End (E2E) Scenario Testing

*   **Focus:** Simulating complete user and system workflows across all components (smart contracts, backend services, potentially UI).
*   **Method:** Use scripting (e.g., `forge script`, Rust, Python, JavaScript with `ethers.js`/`web3.js`) to orchestrate complex scenarios.
*   **Coverage - Example Scenarios:**
    1.  **Admin Setup:** Admin wallet sets initial parameters on all contracts and grants necessary roles (inter-contract and to operational wallets like data submitter).
    2.  **Successful Data Processing & Reward Claim:**
        *   Data Submitter submits a valid `EnergyDataBatch`.
        *   Wait for challenge period.
        *   Anyone (or a keeper bot) calls `processBatch`.
        *   Verify OGCC minted to treasury.
        *   Verify `NodeContributionUpdated` in `RewardDistributor`.
        *   Node operator calls `claimableRewards` and `claimRewards`; verify USDC transfer.
    3.  **Credit Exchange & Reward Funding:**
        *   User approves `CarbonCreditExchange` to spend their OGCC.
        *   User calls `exchangeCreditsForUSDC`.
        *   Verify user receives USDC, OGCC transferred to treasury.
        *   Verify `RewardsPoolFunded` event from `CarbonCreditExchange` (implies `RewardDistributor.depositRewards` was called).
    4.  **Batch Challenge:**
        *   Data Submitter submits a batch.
        *   Another user challenges the batch within the window.
        *   Admin resolves the challenge (test both upheld and rejected scenarios).
        *   Verify batch processing behaves correctly based on resolution.

### 5.5 Role-Based Access Control (RBAC) Testing

*   **Focus:** Thoroughly verifying all access control mechanisms.
*   **Method:** Programmatic tests attempting to call restricted functions with and without the required roles.
*   **Coverage:**
    *   For every function with a role-based modifier (e.g., `onlyMinter`, `onlyDataSubmitter`, `onlyRole(DEFAULT_ADMIN_ROLE)`):
        *   Test successful execution by an account WITH the role.
        *   Test revert (e.g., `AccessControlUnauthorizedAccount`) for an account WITHOUT the role.
    *   Test `grantRole` and `revokeRole` functionality. Verify `hasRole` reflects changes.
    *   Test that admin of a role can grant/revoke it, and non-admins cannot.

### 5.6 Edge Case and Failure Mode Testing

*   **Focus:** Identifying and testing boundary conditions and potential failure points.
*   **Coverage:**
    *   **Zero values/empty inputs:** where not allowed.
    *   **Extremely large values:** for amounts, scores, etc. (potential for overflow if not using safe math, though OpenZeppelin contracts handle this well).
    *   **Insufficient funds:** for token transfers, USDC payments, reward claims.
    *   **Insufficient allowances:** for ERC20 `transferFrom` operations.
    *   **Contract paused states:** Verify functions behave as expected (revert or allow) when contracts are paused/unpaused.
    *   **Re-entrancy:** Although re-entrancy guards are used, complex call chains could be analyzed. Static analysis tools can also help here.
    *   **Timestamp manipulations (dev network):** Test behavior around `batchProcessingDelay` and challenge windows.
    *   **Transaction ordering/front-running:** Consider if any functions are vulnerable (less common for these types of contracts but good to keep in mind for exchange mechanics).

### 5.7 Security-Specific Testing

*   **Focus:** Addressing specific security concerns, especially for complex logic.
*   **Coverage:**
    *   **P2P Consensus Verification (`EnergyDataBridge._verifyP2PConsensus`):** Once the *actual* multi-signature verification logic is implemented, it requires rigorous testing:
        *   Valid signatures from sufficient active nodes.
        *   Invalid/forged signatures.
        *   Signatures from inactive/unregistered nodes.
        *   Insufficient number of valid signatures.
        *   Replay attacks on signatures (if applicable to the scheme).
    *   **Challenge mechanism:** Test all paths through the challenge submission and resolution.
    *   **Economic exploits:** Consider if any parameter settings or interactions could be exploited for economic gain unfairly (e.g., manipulating exchange rates, reward rates just before/after actions).

### 5.8 Testing Environments

1.  **Local Development Network:**
    *   **Tool:** Anvil (part of Foundry) or Hardhat Network.
    *   **Purpose:** Rapid iteration, unit tests, initial integration tests. Full control over time, accounts, and balances.
2.  **Public Testnet:**
    *   **Examples:** Sepolia (recommended), Goerli (deprecated but still active).
    *   **Purpose:** Staging environment that closely mimics mainnet conditions. Test with testnet versions of USDC, deploy all contracts, and perform E2E testing with the integrated backend. Allows for external party interaction if needed.
3.  **Mainnet (Pre-Launch):**
    *   Potentially a "soft launch" or phased rollout with limited capital/users if applicable, after extensive testnet validation and audits.

### 5.9 Recommended Tooling

*   **Foundry (`forge test`, `forge script`, `cast`):** Primary tool for Solidity-based testing and scripting interactions.
*   **Rust Testing Framework:** For backend integration tests (`cargo test` with appropriate crates for blockchain interaction like `ethers-rs`).
*   **JavaScript/Python Scripting:** (e.g., `ethers.js`, `web3.py`) For more complex E2E scenarios or tools that need to interact with both backend and contracts.
*   **Static Analysis Tools:** Slither, Mythril (for identifying potential vulnerabilities in Solidity code).
*   **Formal Verification Tools (Advanced):** Certora Prover (for proving properties about smart contract behavior).
*   **Security Audits:** Engage reputable third-party auditors before any mainnet deployment involving significant value.

By following this comprehensive setup and testing strategy, you can significantly increase confidence in the correctness, security, and reliability of the OnGrid Protocol system.
