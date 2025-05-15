# OnGrid Protocol Node Integration Guide (Updated)

## Overview

This guide provides step-by-step instructions for backend/node developers (specifically using Rust) to integrate the OnGrid Protocol smart contracts. It covers functionalities relevant to the node architecture, including data submission, reward distribution, administrative operations, and a comprehensive testing plan.

**Assumptions:**
*   You have access to the contract ABIs (JSON files) and deployed contract addresses.
*   You are using a Rust environment with a library like `ethers-rs` or `web3-rs` for blockchain interaction.
*   Numbers representing `uint256` or other large integer types from contracts should be handled as strings or appropriate big number types in Rust (e.g., `U256` from `ethers-rs`) to avoid precision issues. `uint64` or smaller can often be Rust's native integer types if they fit, but string representations are safer for consistency when interacting with ABI examples.
*   `bytes32` and `bytes` are represented as hex strings (e.g., `"0xabcd..."`) in examples. Your Rust library will handle the conversion to actual byte arrays.
*   OGCC (`CarbonCreditToken`) has 3 decimals (1 OGCC token = 1000 smallest units).
*   USDC (Reward Token / Exchange Token) is assumed to have 6 decimals (1 USDC = 1,000,000 smallest units).

## General Node/Backend Setup

1.  **Blockchain Connection:** Establish a connection to the Ethereum node (e.g., via HTTP or WebSocket).
2.  **Wallet/Signer (for transactions):** For operations that modify state (e.g., submitting data, admin functions), the backend service will need access to a wallet/signer with sufficient gas and appropriate roles/permissions on the contracts. This will typically be:
    *   A **Data Submitter Wallet**: Holding the `DATA_SUBMITTER_ROLE` on the `EnergyDataBridge` for submitting energy data.
    *   An **Admin Wallet/Service Wallet**: Holding necessary admin roles if the backend automates administrative tasks or provides an API for them (e.g., `NODE_MANAGER_ROLE`, `PAUSER_ROLE`, or even `DEFAULT_ADMIN_ROLE` on relevant contracts).
    *   Consider security best practices for managing these private keys (e.g., HSM, secrets manager).
3.  **Contract Instances:** For each contract, create an instance in your Rust code using its ABI and address.
    ```rust
    // Conceptual example with ethers-rs
    // use ethers::prelude::*;
    // use ethers::providers::{Provider, Http};
    // use ethers::contract::Contract;
    // use std::sync::Arc;
    // use std::str::FromStr; // For Address::from_str

    // async fn setup_contracts(rpc_url: &str, contract_address_str: &str, contract_abi_json: &str) -> Result<Contract<Provider<Http>>, Box<dyn std::error::Error>> {
    //     let provider = Provider::<Http>::try_from(rpc_url)?;
    //     let client = Arc::new(provider);
    //
    //     let contract_address: Address = Address::from_str(contract_address_str)?;
    //     let contract_abi: Abi = serde_json::from_str(contract_abi_json)?;
    //     let contract_instance = Contract::new(contract_address, contract_abi, Arc::clone(&client));
    //     Ok(contract_instance)
    // }
    //
    // // To send transactions, you'll need a SignerMiddleware
    // // let wallet: LocalWallet = "YOUR_PRIVATE_KEY".parse()?;
    // // let chain_id = provider.get_chainid().await?.as_u64(); // Or set directly
    // // let signer_client = SignerMiddleware::new(client, wallet.with_chain_id(chain_id));
    // // let contract_with_signer = Contract::new(contract_address, contract_abi, Arc::new(signer_client));
    ```
4.  **BigNumber/String Handling:** Ensure all `uint` and `int` values from contracts are handled appropriately (e.g., `U256` in `ethers-rs`, or strings if passing through APIs) to prevent precision loss. When sending these values to contracts, they should also be formatted correctly.
5.  **Event Listening:** Implement logic to listen for relevant smart contract events. This is crucial for tracking state changes, data submissions, reward distributions, etc.

## Contract Integration Order & Node Architecture Focus

The following order is recommended for integrating the contracts into your node architecture. The primary focus for the node system will be the `EnergyDataBridge`, data processing, and interactions with the `RewardDistributor`.

1.  **`CarbonCreditToken` (OGCC):** Foundational token contract.
2.  **`RewardDistributor`:** Manages USDC rewards for node operators. The `EnergyDataBridge` will update contributions here.
3.  **`EnergyDataBridge`:** Central to the node architecture. Nodes are expected to submit verified energy data batches and monitor their processing.
4.  **`CarbonCreditExchange`:** Facilitates OGCC for USDC swaps.

---

## Step 1: `CarbonCreditToken` (OGCC) Integration

This contract manages the OnGrid Carbon Credit (OGCC) ERC20 token. OGCC has **3 decimals**.

### Functions (Node-Relevant)

#### `balanceOf(address account)`
*   **Purpose:** Get the OGCC token balance of an account.
*   **Inputs:** `account` (address)
*   **Outputs:** `balance` (`uint256`, smallest units)
*   **Node Interaction:** Useful for displaying balances (e.g., treasury, user wallets if the backend provides this info).

#### `allowance(address owner, address spender)`
*   **Purpose:** Check the amount of tokens an `owner` allowed a `spender`. Critical for `CarbonCreditExchange`.
*   **Inputs:** `owner` (address), `spender` (address, e.g., `CarbonCreditExchange` address)
*   **Outputs:** `remaining` (`uint256`, smallest units)
*   **Node Interaction:** The backend might check allowances if it facilitates transactions or provides information to users about the `CarbonCreditExchange`.

#### `approve(address spender, uint256 value)`
*   **Purpose:** Allow a `spender` (e.g., `CarbonCreditExchange` contract) to withdraw tokens from the caller.
*   **Inputs:** `spender` (address), `value` (`uint256`, smallest units)
*   **Outputs:** (Transaction receipt) Returns `true`.
*   **Events Emitted:** `Approval`
*   **Node Interaction:** Typically user-initiated. If the backend manages a treasury wallet that will sell credits on the `CarbonCreditExchange`, the backend would need to call `approve` on behalf of that treasury wallet, targeting the `CarbonCreditExchange` address.

#### `protocolTreasury()`
*   **Purpose:** Get the address of the protocol treasury.
*   **Outputs:** `address`
*   **Node Interaction:** Useful if the backend needs to know where OGCC tokens are directed (e.g., upon exchange via `CarbonCreditExchange`).

### Events (Node-Relevant)

#### `Transfer(address indexed from, address indexed to, uint256 value)`
*   **Purpose:** Emitted when tokens are transferred, including mints (from zero address to treasury), burns (from an account to zero address), and regular transfers.
*   **Payload:** `from` (address), `to` (address), `value` (`uint256`, smallest units)
*   **Node Action:** Monitor for analytics, tracking treasury movements, or user balances.

#### `Approval(address indexed owner, address indexed spender, uint256 value)`
*   **Purpose:** Emitted on a successful call to `approve`.
*   **Payload:** `owner` (address), `spender` (address), `value` (`uint256`, smallest units)
*   **Node Action:** Monitor if tracking allowances for specific contracts (like `CarbonCreditExchange`) is needed.

#### `ProtocolTreasuryChanged(address indexed newTreasury)`
*   **Purpose:** Emitted when the protocol treasury address is updated.
*   **Payload:** `newTreasury` (address)
*   **Node Action:** Update any internally cached treasury address.

---

## Step 2: `RewardDistributor` Integration

Manages USDC rewards for node operators. USDC has **6 decimals**. `REWARD_PRECISION` in the contract is `1e18`.

### Functions (Node Operator / System Relevant)

#### `claimableRewards(address operator)`
*   **Purpose:** Calculates USDC rewards a node operator can claim.
*   **Inputs:** `operator` (address)
*   **Outputs:** `pendingRewards` (`uint256`, USDC smallest units)
*   **Node Interaction:** Backend can call this to display claimable rewards for operators.

#### `claimRewards()`
*   **Purpose:** Allows the calling node operator (`msg.sender`) to claim accrued USDC rewards.
*   **Inputs:** None.
*   **Events Emitted:** `RewardsClaimed`
*   **Node Interaction:** If operators manage their own wallets, they initiate this. If the backend manages operator wallets for claims, it would call this.

#### `nodeInfo(address operator)`
*   **Purpose:** Retrieves information about a node operator.
*   **Inputs:** `operator` (address)
*   **Outputs:** `contributionScore` (`uint256`), `rewardDebt` (`uint256`)
*   **Node Interaction:** Useful for displaying operator statistics.

#### `updateNodeContribution(address operator, uint256 contributionDelta, uint64 timestamp)`
*   **Purpose:** Updates the contribution score for a node operator. **This will be called by the `EnergyDataBridge` contract.**
*   **Inputs:** `operator` (address), `contributionDelta` (`uint256`), `timestamp` (`uint64`)
*   **Events Emitted:** `NodeContributionUpdated`
*   **Node Interaction:** The backend (acting as `EnergyDataBridge` or through it) is responsible for ensuring this is called indirectly via `EnergyDataBridge.processBatch()`. The `EnergyDataBridge` needs `METRIC_UPDATER_ROLE` on this contract.

### Events (Node Operator / System Relevant)

#### `RewardsClaimed(address indexed operator, uint256 amount)`
*   **Purpose:** Emitted when an operator claims rewards.
*   **Payload:** `operator` (address), `amount` (`uint256`, USDC smallest units)
*   **Node Action:** Monitor to track claims, update operator dashboards.

#### `NodeContributionUpdated(address indexed operator, uint256 newScore, uint64 timestamp)`
*   **Purpose:** Emitted when an operator's contribution score is updated (called by `EnergyDataBridge`).
*   **Payload:** `operator` (address), `newScore` (`uint256`), `timestamp` (`uint64`)
*   **Node Action:** Crucial. Update displayed scores, verify contributions are reflected.

---

## Step 3: `EnergyDataBridge` Integration

Central to the node architecture. Nodes submit energy data, monitor status, and potentially manage challenges.

**Data Structures (Essential for `submitEnergyDataBatch`):**

*   **`EnergyData` struct (Solidity):**
    ```solidity
    struct EnergyData {
        bytes32 deviceId;
        address nodeOperatorAddress;
        uint256 energyKWh; // e.g., 1500 for 1.5 kWh (no contract-side decimals)
        uint64 timestamp;
    }
    ```
    *   **Example for one entry (JSON representation for Rust):**
        ```json
        {
          "deviceId": "0xdevicehash...",
          "nodeOperatorAddress": "0xNodeOpAddress...",
          "energyKWh": "1500", // Represents 1.5 kWh.
          "timestamp": "1678886000"
        }
        ```

*   **`P2PConsensusProof` struct (Solidity):**
    ```solidity
    struct P2PConsensusProof {
        bytes32 consensusRoundId;
        uint256 participatingNodeCount;
        bytes32 consensusResultHash; // hash of (consensusRoundId, keccak256(abi.encode(dataBatch)))
        bytes multiSignature; // Aggregated signatures
    }
    ```
    *   **Example (JSON representation for Rust):**
        ```json
        {
          "consensusRoundId": "0xroundIdHash...",
          "participatingNodeCount": "5",
          "consensusResultHash": "0xbatchDataCombinedHash...",
          "multiSignature": "0xaggregatedSigsHex..." // e.g., "0x1234abcd..."
        }
        ```

### Functions (Node Core Functionality)

#### `submitEnergyDataBatch(EnergyData[] calldata dataBatch, P2PConsensusProof calldata consensusProof)`
*   **Purpose:** Submits a batch of energy data with P2P consensus proof.
*   **Inputs:** `dataBatch` (`EnergyData[]`), `consensusProof` (`P2PConsensusProof`)
*   **Events Emitted:** `EnergyDataSubmitted`
*   **Node Interaction (Backend Responsibility):**
    1.  Aggregating `EnergyData` from devices/operators.
    2.  Facilitating off-chain P2P consensus to generate the `P2PConsensusProof`, including `consensusResultHash` and `multiSignature`.
        *   `batchDataHash = keccak256(abi.encode(dataBatch))`
        *   `consensusResultHash = keccak256(abi.encode(consensusProof.consensusRoundId, batchDataHash))`
    3.  The backend service/wallet calling this function MUST have the `DATA_SUBMITTER_ROLE`.
    4.  **CRITICAL:** The `_verifyP2PConsensus` function in the smart contract is currently a **placeholder**. The security and validity of the system depend on the off-chain P2P consensus being robust and the `multiSignature` being correctly generated. A future contract upgrade will implement on-chain multi-signature verification against registered nodes using this `multiSignature` data.

#### `processBatch(bytes32 batchHash)`
*   **Purpose:** Processes a submitted batch after the challenge period, mints credits, and updates node contributions.
*   **Inputs:** `batchHash` (`bytes32` - keccak256 hash of the `EnergyData[]` array)
*   **Events Emitted:** `EnergyDataProcessed` (on success)
*   **Node Interaction:**
    1.  Backend should monitor submitted batches (via `EnergyDataSubmitted` event and `batchSubmissionTimes(batchHash)` view function).
    2.  Once `block.timestamp >= batchSubmissionTimes[batchHash]`, and if `batchChallenges[batchHash]` shows no active/upheld challenge, this function can be called.
    3.  This might be triggered by a keeper bot managed by the backend, or an admin action via a backend API.
    4.  This function internally calls `carbonCreditToken.mintToTreasury()` (requires `EnergyDataBridge` to have `MINTER_ROLE` on `CarbonCreditToken`) and `rewardDistributor.updateNodeContribution()` (requires `EnergyDataBridge` to have `METRIC_UPDATER_ROLE` on `RewardDistributor`).

### View Functions (Node Informational & Monitoring)

*   `emissionFactor()`: Returns `uint256` (grams CO2e * 1e6 / kWh).
*   `requiredConsensusNodes()`: Returns `uint256`.
*   `batchProcessingDelay()`: Returns `uint256` (seconds).
*   `batchSubmissionTimes(bytes32 batchHash)`: Returns `uint256` (Unix timestamp, 0 if not submitted).
*   `processedBatchHashes(bytes32 batchHash)`: Returns `bool`.
*   `batchChallenges(bytes32 batchHash)`: Returns `BatchChallenge` struct.
*   `registeredNodes(bytes32 peerId)`: Returns `RegisteredNode` struct.
*   `getPeerIdCount()`: Returns `uint256`.
*   `peerIds(uint256 index)`: Returns `bytes32`.

### Functions (Challenge-Related - Backend may interact)

#### `challengeBatch(bytes32 batchHash, string calldata reason)`
*   **Purpose:** Allows anyone to challenge a submitted batch.
*   **Inputs:** `batchHash` (`bytes32`), `reason` (string)
*   **Events Emitted:** `BatchChallenged`
*   **Node Interaction:** The backend might include logic to flag suspicious data or allow admins/operators (via a backend-controlled interface) to initiate challenges.

### Events (Node Core Monitoring)

*   `EnergyDataSubmitted(bytes32 indexed batchHash, uint256 entriesSubmitted, uint256 processAfterTimestamp)`: Track `batchHash` and `processAfterTimestamp`.
*   `EnergyDataProcessed(bytes32 indexed batchHash, uint256 totalCreditsMinted, uint256 entriesProcessed)`: Update batch status, log mints.
*   `BatchChallenged(bytes32 indexed batchHash, address indexed challenger, string reason)`: Update batch status to "Challenged", alert systems.
*   `ChallengeResolved(bytes32 indexed batchHash, bool isUpheld)`: Update batch status based on resolution.
*   `NodeRegistered(bytes32 indexed peerId, address indexed operator)`: Update internal list of P2P nodes.
*   `NodeStatusUpdated(bytes32 indexed peerId, bool isActive)`: Update P2P node status.

---

## Step 4: `CarbonCreditExchange` Integration

Allows users to exchange OGCC for USDC. The backend might monitor this for analytics or manage treasury interactions.

### Functions (User / Monitoring / Backend-Treasury Relevant)

#### `exchangeCreditsForUSDC(uint256 creditAmount)`
*   **Purpose:** Allows an account to sell their OGCC for USDC.
*   **Inputs:** `creditAmount` (`uint256`, OGCC smallest units)
*   **Events Emitted:** `CreditsExchanged`, `RewardsPoolFunded`
*   **Node Interaction:**
    1.  **User Action Required Pre-call:** The account selling OGCC (e.g., user, or a treasury wallet managed by the backend) must first call `CarbonCreditToken.approve(CarbonCreditExchangeAddress, creditAmount)` to allow the `CarbonCreditExchange` to spend their OGCC.
    2.  The `CarbonCreditExchange` will then call `IERC20(carbonCreditTokenAddress).transferFrom(caller, cctProtocolTreasury, creditAmount)`.
    3.  The backend may monitor this for system analytics. If the backend is managing a treasury wallet that sells OGCC, it would orchestrate the `approve` and then this `exchangeCreditsForUSDC` call.
    4.  **USDC Liquidity:** The `CarbonCreditExchange` contract needs to be funded with USDC to pay sellers. This is an external operational concern. Reverts with `InsufficientUSDCLiquidity` if funds are low.
    5.  **Reward Funding:** A portion of fees is sent to `RewardDistributor`. This requires:
        *   `CarbonCreditExchange` to have `REWARD_DEPOSITOR_ROLE` on `RewardDistributor`.
        *   `CarbonCreditExchange` (as `msg.sender` to `depositRewards`) must `approve` the `RewardDistributor` to spend its (the Exchange's) USDC. This is an operational step, likely managed by an admin or specialized service. The `try/catch` in the contract means the exchange might proceed even if reward deposit fails, but `RewardsPoolFunded` won't emit.

### View Functions (Monitoring Relevant)

*   `exchangeRate()`: Returns `uint256` (USDC smallest units per 1 OGCC *token*).
*   `protocolFeePercentage()`: Returns `uint256` (scaled by 1e6, e.g., 150,000 for 15%).
*   `rewardDistributorPercentage()`: Returns `uint256` (scaled by 1e6).
*   `exchangeEnabled()`: Returns `bool`.
*   `totalCreditsExchanged()`, `totalUsdcCollected()`, `totalProtocolFees()`, `totalRewardsFunded()`: Return `uint256`.

### Events (Monitoring Relevant)

*   `CreditsExchanged(address indexed user, uint256 creditAmount, uint256 usdcAmount, uint256 feeAmount)`: Monitor for analytics.
*   `RewardsPoolFunded(uint256 amount)`: Monitor to track reward pool funding.
*   `ExchangeRateSet`, `ProtocolFeeSet`, `RewardDistributorPercentageSet`, `USDCTokenSet`, `ExchangeStatusChanged`: Monitor for changes in exchange parameters.

---

## Administrative Functions (for Backend-managed Admin Operations)

If the backend service uses a wallet with administrative roles, it can call these functions. The caller (`msg.sender` which is the backend's service wallet) must have the appropriate role on the respective contract.

### 1. `CarbonCreditToken` (Admin Ops via Backend)
*   `setProtocolTreasury(address _newTreasury)` (Requires `DEFAULT_ADMIN_ROLE`)
*   `grantRole(bytes32 role, address account)` / `revokeRole(bytes32 role, address account)` (Requires admin of the role being managed)
    *   Roles to manage: `MINTER_ROLE`, `TREASURY_MANAGER_ROLE`, `PAUSER_ROLE`.
*   `pause()` / `unpause()` (Requires `PAUSER_ROLE`)
*   `transferFromTreasury(address to, uint256 amount)` (Requires `TREASURY_MANAGER_ROLE`)
*   `retireFromTreasury(uint256 amount, string calldata reason)` (Requires `TREASURY_MANAGER_ROLE`)

### 2. `RewardDistributor` (Admin Ops via Backend)
*   `setRewardRate(uint256 _rate)` (Requires `DEFAULT_ADMIN_ROLE`)
*   `grantRole(bytes32 role, address account)` / `revokeRole(bytes32 role, address account)`
    *   Roles to manage: `REWARD_DEPOSITOR_ROLE`, `METRIC_UPDATER_ROLE`, `PAUSER_ROLE`.
*   `pause()` / `unpause()` (Requires `PAUSER_ROLE`)
*   `depositRewards(uint256 amount)` (Requires `REWARD_DEPOSITOR_ROLE` and the backend service wallet must `approve` this contract to spend its USDC).

### 3. `EnergyDataBridge` (Admin Ops via Backend)
*   `setEmissionFactor(uint256 _factor)` (Requires `DEFAULT_ADMIN_ROLE`)
*   `setRequiredConsensusNodes(uint256 _requiredNodes)` (Requires `DEFAULT_ADMIN_ROLE`)
*   `setBatchProcessingDelay(uint256 _delayInSeconds)` (Requires `DEFAULT_ADMIN_ROLE`)
*   `registerNode(bytes32 _peerId, address _operator)` (Requires `NODE_MANAGER_ROLE`)
*   `updateNodeStatus(bytes32 _peerId, bool _isActive)` (Requires `NODE_MANAGER_ROLE`)
*   `resolveChallenge(bytes32 batchHash, bool isUpheld)` (Requires `DEFAULT_ADMIN_ROLE`)
*   `grantRole(bytes32 role, address account)` / `revokeRole(bytes32 role, address account)`
    *   Roles to manage: `DATA_SUBMITTER_ROLE`, `NODE_MANAGER_ROLE`, `PAUSER_ROLE`.
*   `pause()` / `unpause()` (Requires `PAUSER_ROLE`)

### 4. `CarbonCreditExchange` (Admin Ops via Backend)
*   `setExchangeRate(uint256 _newRate)` (Requires `RATE_SETTER_ROLE`)
*   `setProtocolFee(uint256 _newFeePercentage)` (Requires `EXCHANGE_MANAGER_ROLE`)
*   `setRewardDistributorPercentage(uint256 _newPercentage)` (Requires `EXCHANGE_MANAGER_ROLE`)
*   `setUSDCToken(address _newUsdcToken)` (Requires `EXCHANGE_MANAGER_ROLE`)
*   `setExchangeEnabled(bool _enabled)` (Requires `EXCHANGE_MANAGER_ROLE`)
*   `grantRole(bytes32 role, address account)` / `revokeRole(bytes32 role, address account)`
    *   Roles to manage: `RATE_SETTER_ROLE`, `EXCHANGE_MANAGER_ROLE`, `PAUSER_ROLE`.
*   `pause()` / `unpause()` (Requires `PAUSER_ROLE`)

---

## Backend Integration Testing Plan

This plan focuses on how the Rust backend developer should test their service's interactions with the smart contracts.

### A. Prerequisites for Testing
1.  **Deployed Contracts:** All OnGrid smart contracts deployed to a test network (e.g., Anvil, Sepolia).
2.  **Test Accounts:**
    *   **Deployer Account:** With `DEFAULT_ADMIN_ROLE` on all contracts (as per deployment script).
    *   **Backend Service Wallets:**
        *   One for `DATA_SUBMITTER_ROLE` on `EnergyDataBridge`.
        *   One for any administrative tasks the backend might perform (e.g., `NODE_MANAGER_ROLE` on `EnergyDataBridge`, or roles on other contracts if the backend automates admin functions).
    *   **User/Node Operator Accounts:** Several test accounts with test ETH and test USDC/OGCC.
3.  **Test Tokens:**
    *   Mock USDC deployed or a faucet for testnet USDC.
    *   OGCC will be minted by the `EnergyDataBridge`.
4.  **Initial Role Setup:** Use the Deployer Account to grant necessary inter-contract roles and roles to backend service wallets as outlined in the "Admin and Inter-Contract Setup Guide".
5.  **Backend Test Environment:** Configured to connect to the chosen test network.

### B. Unit/Component Tests for Backend Modules
*   **Focus:** Test individual backend modules that interact with specific contract functions in isolation.
*   **Method:** Use Rust's testing framework (`cargo test`). Mock blockchain interactions or use a local Anvil instance for fast feedback.
*   **Coverage:**
    *   **ABI Interaction:** Test functions that load ABIs and create contract instances.
    *   **Parameter Serialization:** Verify correct serialization of Rust types (e.g., `U256`, `Address`, `Vec<u8>`, structs) to ABI-encoded data for contract calls.
    *   **Return Value Deserialization:** Verify correct deserialization of contract call results and event data into Rust types.
    *   **Error Code Mapping:** Test mapping of common contract error strings/signatures (from `Errors.sol`) to backend-specific errors or statuses.

### C. Integration Tests: Backend <-> Smart Contracts
*   **Focus:** Verify direct interactions between the backend service and live (testnet) smart contracts.
*   **Method:** Use Rust's testing framework, making actual RPC calls to contracts on Anvil or a public testnet.
*   **Coverage:**
    1.  **View Function Calls:**
        *   Call all relevant view functions on each contract (e.g., `EnergyDataBridge.batchSubmissionTimes`, `RewardDistributor.claimableRewards`, `CarbonCreditExchange.exchangeRate`, `CarbonCreditToken.balanceOf`).
        *   Assert that the returned data is correctly parsed and matches expected values based on pre-set contract states.
    2.  **Transaction Submissions (using Backend Service Wallets):**
        *   **`EnergyDataBridge.submitEnergyDataBatch`:**
            *   As `DATA_SUBMITTER_ROLE`: Successfully submit a batch. Verify transaction success and `EnergyDataSubmitted` event.
            *   Attempt with incorrect/missing role: Verify transaction reverts with an access control error, and the backend handles it.
            *   Test with invalid batch data (e.g., empty, malformed proof): Verify contract reverts and backend handles it.
        *   **`EnergyDataBridge.processBatch` (if backend acts as keeper):**
            *   Call after delay and no challenge: Verify success and `EnergyDataProcessed` event.
            *   Call before delay: Verify revert.
            *   Call if challenged and not resolved: Verify revert.
        *   **Administrative Functions (if backend manages them):**
            *   For each admin function the backend might call (e.g., `EnergyDataBridge.registerNode`, `CarbonCreditExchange.setExchangeRate`):
                *   Test successful call with the correct admin role.
                *   Test revert if called by a wallet without the specific role.
                *   Verify event emissions.
    3.  **Event Subscription and Processing:**
        *   Set up backend listeners for all critical events from all contracts (e.g., `EnergyDataSubmitted`, `EnergyDataProcessed`, `BatchChallenged`, `ChallengeResolved`, `NodeContributionUpdated`, `RewardsClaimed`, `CreditsExchanged`, `RewardsPoolFunded`, `RoleGranted`, `Paused`).
        *   Trigger these events by interacting with the contracts.
        *   Verify the backend correctly receives, parses, and processes the event data (e.g., updates its internal database, triggers alerts, logs information).
        *   Test filtering capabilities if used (e.g., listening for events related to specific batch hashes or users).

### D. Scenario-Based Testing (from Backend Perspective)
*   **Focus:** Simulate key system flows involving the backend.
*   **Method:** Orchestrate multi-step scenarios, potentially involving multiple contract interactions initiated or monitored by the backend.
*   **Coverage - Example Scenarios:**
    1.  **Full Data Lifecycle Driven/Monitored by Backend:**
        *   Backend (as `DATA_SUBMITTER_ROLE`) calls `EnergyDataBridge.submitEnergyDataBatch`.
        *   Backend monitors for `EnergyDataSubmitted` event.
        *   Backend (as keeper or via admin trigger) calls `EnergyDataBridge.processBatch` after delay.
        *   Backend monitors for `EnergyDataProcessed` from `EnergyDataBridge`.
        *   Backend monitors for `Transfer` (mint) from `CarbonCreditToken`.
        *   Backend monitors for `NodeContributionUpdated` from `RewardDistributor`.
    2.  **Challenge Monitoring by Backend:**
        *   Submit a batch.
        *   Manually challenge the batch.
        *   Backend monitors for `BatchChallenged` event and updates its internal state for the batch.
        *   Admin resolves the challenge (test both upheld/rejected via a manual call or admin interface backed by the backend).
        *   Backend monitors for `ChallengeResolved` and updates batch state accordingly. If rejected and processable, backend triggers `processBatch`.
    3.  **Exchange Monitoring & Treasury Action (if applicable):**
        *   Manually perform an OGCC-to-USDC exchange.
        *   Backend monitors `CreditsExchanged` and `RewardsPoolFunded`.
        *   If backend manages a treasury wallet:
            *   Treasury wallet (via backend) `approve`s `CarbonCreditExchange`.
            *   Treasury wallet (via backend) calls `exchangeCreditsForUSDC`.
            *   Verify outcomes and events.
    4.  **Node Registration/Management (if backend provides API):**
        *   Backend (using wallet with `NODE_MANAGER_ROLE`) calls `EnergyDataBridge.registerNode`. Verify `NodeRegistered`.
        *   Backend calls `EnergyDataBridge.updateNodeStatus`. Verify `NodeStatusUpdated`.

### E. Backend Error Handling and Resilience
*   **Focus:** How the backend handles failures during contract interaction.
*   **Coverage:**
    *   **Contract Reverts:** Test backend response to:
        *   Access control errors (e.g., `CallerNotDataSubmitter`, `AccessControlUnauthorizedAccount`).
        *   State-based errors (e.g., `BatchAlreadyProcessed`, `ChallengePeriodNotOver`, `ExchangeDisabled`).
        *   Input validation errors (e.g., `ZeroAddress`, `InvalidAmount`).
        *   `InsufficientUSDCLiquidity` from `CarbonCreditExchange`.
        *   `InsufficientFundsForRewards` from `RewardDistributor` (for claims).
    *   **Network/RPC Issues:** Simulate RPC node downtime or slow responses. Verify backend retry mechanisms, timeouts, and error reporting.
    *   **Gas Issues:** Test scenarios with insufficient gas for transactions or gas estimation failures. Verify backend handling.
    *   **Nonce Management:** If the backend manages wallets, ensure correct nonce handling for transactions, especially with retries.

### F. Security Considerations for Backend Testing
*   **Private Key Management:** While not a contract test, ensure the backend's key management is secure and tested.
*   **Input Sanitization:** If the backend takes inputs that are passed to contracts, ensure they are sanitized to prevent unexpected behavior.
*   **Replay Protection for Off-Chain Data:** For data passed to `P2PConsensusProof`, ensure the backend's off-chain consensus mechanism prevents replay attacks before data even reaches the `submitEnergyDataBatch` function. The `consensusRoundId` and `batchHash` checks in `_verifyP2PConsensus` help, but the primary P2P layer is off-chain.

---

This guide, along with the contract ABIs, should provide a solid foundation for the Rust backend developer. They should always consult the ABIs for exact function signatures, event names, and parameter types.