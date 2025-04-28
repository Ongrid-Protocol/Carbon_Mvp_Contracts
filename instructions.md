# OnGrid Carbon Contracts - Technical PRD (MVP v1.0)

*(Consolidated implementation brief for AI code generation - Carbon/Energy Stack Only)*
*(Date: 25 Apr 2025)*

## 1. Project Overview

This document outlines the technical requirements for the **OnGrid Carbon Credit & Energy Tracking Smart Contracts (MVP)**. This system complements the OnGrid Finance stack by providing infrastructure for verifying clean energy generation data, minting corresponding carbon credits, and distributing rewards to network participants (node operators). It operates on the Base blockchain (Sepolia testnet and Mainnet).

The core purpose is to translate verified off-chain energy data from solar installations (monitored by OnGrid's DePin network) into on-chain value:
1.  **Data Onboarding:** An oracle bridge (`EnergyDataBridge`) receives verified energy production data batches from trusted off-chain sources.
2.  **Carbon Credit Minting:** Based on the submitted data and configurable emission factors, Carbon Credits (`CarbonCreditToken`) representing tonnes of CO2e avoided are minted.
3.  **Credit Custody:** Minted credits are held by the central Protocol Treasury.
4.  **Reward Distribution:** A portion of protocol revenue or other designated funds is distributed as rewards (in stablecoins like USDC) to the node operators who contribute data, managed by the `RewardDistributor`.

**Key System Features:**
* Secure and efficient onboarding of aggregated energy data via a trusted oracle mechanism.
* Gas-efficient data submission using sponsored transactions (managed off-chain).
* Standardized ERC20 Carbon Credit token with controlled minting.
* Clear separation between carbon credit ownership (Protocol) and node operator rewards (value distribution).
* UUPS upgradeability for future enhancements.

**Out of Scope (MVP):** On-chain verification of individual device signatures (relies on trusted off-chain aggregation/signing), direct carbon credit market integration/listing, complex reward streaming mechanisms (uses periodic claims), on-chain testing framework specification (covered separately).

## 2. Frameworks and Libraries

* **Solidity:** `^0.8.25`
* **Blockchain:** Base Mainnet & Base Sepolia Testnet
* **Development Tooling:** Foundry (`forge`, `anvil`, `cast`)
* **Primary Reward Asset:** USDC (6 decimals) - *Assumed, requires confirmation or configuration.*
* **Core Dependencies:**
    * **OpenZeppelin Contracts (`v5.*`)**: `ERC20`, `ERC20Burnable`, `AccessControl`, `Ownable`, `Pausable`, `ReentrancyGuard`, `UUPSUpgradeable`, `SafeERC20`, `ECDSA` (optional, if signature verification is done on-chain later).
    * **Solmate (`v7.*`)**: Optional helpers if needed for gas optimization.
    * **Forge-Std (`latest`)**: `Vm`, `StdCheats` (for deployment/upgrade scripts).

## 3. Core Contract Functionalities & Specifications

*(Contracts listed align with the file structure in Section 7)*

### 3.1 `EnergyDataBridge.sol` (src/bridge/)

* **Inherits:** `AccessControl`, `Pausable`, `UUPSUpgradeable`.
* **Purpose:** Acts as the trusted on-chain entry point for verified energy data batches submitted by off-chain node aggregators/oracles. Processes data to trigger carbon credit minting and potentially update node operator metrics for rewards.
* **Roles:** `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `UPGRADER_ROLE`, `DATA_SUBMITTER_ROLE` (trusted off-chain service/oracle).
* **State:**
    * `ICarbonCreditToken public carbonCreditToken;` // Address of the token contract
    * `IRewardDistributor public rewardDistributor;` // Address of the reward contract
    * `uint256 public emissionFactor; // e.g., grams CO2e per kWh - needs units defined (e.g., grams CO2e * 1e6 / kWh)`
    * `mapping(bytes32 => bool) public processedBatchHashes; // Prevents replay attacks`
* **Key Functions:**
    * `constructor(address _creditToken, address _rewardDistributor)`: Sets addresses, grants roles.
    * `setEmissionFactor(uint256 _factor)`: `external onlyRole(DEFAULT_ADMIN_ROLE)`. Updates the factor used for credit calculation.
    * `submitEnergyDataBatch(EnergyData[] calldata dataBatch)`: `external nonReentrant whenNotPaused onlyRole(DATA_SUBMITTER_ROLE)`.
        * Calculates `batchHash = keccak256(abi.encode(dataBatch))`. Checks `!processedBatchHashes[batchHash]`.
        * Iterates through `dataBatch`:
            * Parses `deviceId`, `energyKWh`, `timestamp`, potentially `nodeOperatorAddress`.
            * Calculates `creditsToMint = (energyKWh * emissionFactor) / (1000 * 1000 * 1000); // Convert grams to tonnes (assuming 3 decimals for token)` - *Refine formula based on chosen units/decimals*.
            * If `creditsToMint > 0`, calls `carbonCreditToken.mintToTreasury(creditsToMint)`.
            * Calls `rewardDistributor.updateNodeContribution(nodeOperatorAddress, energyKWh, timestamp)` (or similar metric update).
        * Marks `processedBatchHashes[batchHash] = true`.
        * Emits `EnergyDataProcessed`.
* **Structs:** `struct EnergyData { bytes32 deviceId; address nodeOperatorAddress; uint256 energyKWh; uint64 timestamp; /* + potentially signature data if verified later */ }`
* **Events:** `EmissionFactorSet(uint256 newFactor)`, `EnergyDataProcessed(bytes32 indexed batchHash, uint256 totalCreditsMinted, uint256 entriesProcessed)`.
* **Note on Gas:** Transactions calling `submitEnergyDataBatch` are expected to be sponsored off-chain by the entity holding the `DATA_SUBMITTER_ROLE`.

### 3.2 `CarbonCreditToken.sol` (src/token/)

* **Inherits:** `ERC20`, `ERC20Burnable`, `AccessControl`, `Pausable`, `UUPSUpgradeable`. (Consider using `ERC20PresetMinterPauser` as a base and modifying).
* **Purpose:** Represents OnGrid Carbon Credits as an ERC20 token. Minting is restricted, and tokens are initially sent to the Protocol Treasury.
* **Roles:** `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `UPGRADER_ROLE`, `MINTER_ROLE` (granted to `EnergyDataBridge`).
* **State:**
    * `address public protocolTreasury;`
* **Key Functions:**
    * `constructor(string memory name, string memory symbol, address _initialAdmin, address _protocolTreasury)`: Sets token details, 3 decimals, grants roles to `_initialAdmin`, sets treasury.
    * `setProtocolTreasury(address _newTreasury)`: `external onlyRole(DEFAULT_ADMIN_ROLE)`. Updates the treasury address.
    * `decimals() returns (uint8)`: `pure override returns (3)`.
    * `mintToTreasury(uint256 amount)`: `external whenNotPaused onlyRole(MINTER_ROLE)`. Calls internal `_mint(protocolTreasury, amount)`. Emits `Transfer` event (from address 0).
* **Events:** Standard ERC20 events (`Transfer`, `Approval`), `ProtocolTreasuryChanged`.

### 3.3 `RewardDistributor.sol` (src/rewards/)

* **Inherits:** `ReentrancyGuard`, `Pausable`, `AccessControl`, `UUPSUpgradeable`.
* **Purpose:** Manages the distribution of rewards (e.g., USDC) to registered node operators based on their contributions (e.g., energy data submitted, uptime). Funds are deposited externally (e.g., from Protocol Treasury or Fee Router allocation).
* **Roles:** `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE`, `UPGRADER_ROLE`, `REWARD_DEPOSITOR_ROLE` (entity funding the contract), `METRIC_UPDATER_ROLE` (`EnergyDataBridge` or other trusted source).
* **State:**
    * `IERC20 public immutable rewardToken; // e.g., USDC address`
    * `struct NodeInfo { uint256 contributionScore; uint256 lastUpdateTime; }`
    * `mapping(address => NodeInfo) public nodeInfo; // operatorAddress => Info`
    * `mapping(address => uint256) public rewardsClaimed; // operatorAddress => amount`
    * `uint256 public currentRewardRate; // e.g., rewardToken units per contributionScore point per second`
    * `uint256 public totalContributionScore;`
    * `uint48 public lastGlobalUpdateTime;`
    * `uint256 public accumulatedRewardsPerScoreUnit; // Tracks rewards accrued per unit of score over time`
* **Key Functions:**
    * `constructor(address _rewardToken)`: Sets reward token, grants roles.
    * `setRewardRate(uint256 _rate)`: `external onlyRole(DEFAULT_ADMIN_ROLE)`. Updates `currentRewardRate`. Requires call to `_updateGlobalRewards()` first.
    * `depositRewards(uint256 amount)`: `external nonReentrant onlyRole(REWARD_DEPOSITOR_ROLE)`. Transfers `rewardToken` from depositor to this contract. Emits `RewardsDeposited`.
    * `updateNodeContribution(address operator, uint256 contributionDelta, uint64 timestamp)`: `external onlyRole(METRIC_UPDATER_ROLE)`. Calls `_updateNodeRewards(operator)` first. Updates `nodeInfo[operator].contributionScore`, `totalContributionScore`, `nodeInfo[operator].lastUpdateTime`. Ensures `timestamp >= nodeInfo[operator].lastUpdateTime`. Emits `NodeContributionUpdated`.
    * `claimableRewards(address operator) returns (uint256)`: `view`. Calculates pending rewards for an operator based on `accumulatedRewardsPerScoreUnit`, `nodeInfo[operator].contributionScore`, and `rewardsClaimed[operator]`. Requires call to `_updateNodeRewards(operator)` conceptually (or recalculate).
    * `claimRewards()`: `external nonReentrant whenNotPaused`. Calculates claimable amount for `msg.sender`. Transfers `rewardToken`. Updates `rewardsClaimed[msg.sender]`. Emits `RewardsClaimed`.
    * `_updateGlobalRewards()`: `internal`. Calculates increase in `accumulatedRewardsPerScoreUnit` based on `currentRewardRate`, `totalContributionScore`, and time since `lastGlobalUpdateTime`. Updates `lastGlobalUpdateTime`.
    * `_updateNodeRewards(address operator)`: `internal`. Calls `_updateGlobalRewards()`. Calculates the rewards accrued specifically for the operator since their `lastUpdateTime` based on their score and the change in `accumulatedRewardsPerScoreUnit`. *This logic prevents looping but requires careful math, similar to staking reward contracts.* Updates `rewardsClaimed` notionally or prepares value for `claimableRewards`.
* **Events:** `RewardRateSet`, `RewardsDeposited`, `NodeContributionUpdated`, `RewardsClaimed`.

## 4. Data Structures (Core Structs)

* `EnergyData` (in `EnergyDataBridge`): `{ bytes32 deviceId; address nodeOperatorAddress; uint256 energyKWh; uint64 timestamp; }`
* `NodeInfo` (in `RewardDistributor`): `{ uint256 contributionScore; uint256 lastUpdateTime; }`

## 5. System Flow & Interactions

1.  **Data Generation & Off-Chain Aggregation:** Individual DePin devices record energy data -> Data sent to off-chain aggregators -> Aggregators verify, bundle data, calculate `batchHash`, and prepare `EnergyData[]` array.
2.  **On-Chain Data Submission:** Trusted Aggregator/Oracle (`DATA_SUBMITTER_ROLE`) calls `EnergyDataBridge.submitEnergyDataBatch` with the data. Gas is sponsored off-chain.
3.  **Bridge Processing:** `EnergyDataBridge` validates batch hash (no replay), iterates data:
    * Calculates credits based on `energyKWh` and `emissionFactor`.
    * Calls `CarbonCreditToken.mintToTreasury`.
    * Calls `RewardDistributor.updateNodeContribution` for the relevant node operator.
4.  **Reward Accrual:** `RewardDistributor` tracks node contributions and calculates claimable rewards based on the set reward rate and available funds.
5.  **Reward Claiming:** Node operator calls `RewardDistributor.claimRewards()` to receive their accumulated rewards (in USDC or other `rewardToken`).

## 6. External Integrations (Off-Chain Interactions)

* **DePin Network / Aggregators:** Off-chain systems responsible for collecting, verifying, and batching energy data before submitting it via the `DATA_SUBMITTER_ROLE`.
* **Gas Sponsoring Service:** An off-chain relayer or service used by the data submitter to pay for the gas costs of calling `submitEnergyDataBatch`.
* **Protocol Treasury / Reward Funding:** Off-chain process or potentially an on-chain automated transfer (e.g., from `FeeRouter` in the finance stack) deposits the `rewardToken` (e.g., USDC) into the `RewardDistributor` via the `REWARD_DEPOSITOR_ROLE`.

## 7. Project File Structure (Foundry)
carbon_contracts/
├── foundry.toml
├── script/
│   ├── DeployCarbonContracts.s.sol
│   └── UpgradeCarbonContracts.s.sol
├── src/
│   ├── common/ # Potentially shared with finance repo or duplicated/namespaced
│   │   ├── Errors.sol
│   │   └── Constants.sol # Carbon-specific constants (e.g., default emission factor)
│   ├── bridge/
│   │   └── EnergyDataBridge.sol
│   ├── token/
│   │   └── CarbonCreditToken.sol
│   ├── rewards/
│   │   └── RewardDistributor.sol
│   └── interfaces/
│       ├── IERC20.sol
│       ├── ICarbonCreditToken.sol
│       ├── IRewardDistributor.sol
│     # └── IEnergyDataBridge.sol (If needed for cross-contract calls)
├── lib/ # Forge dependencies (OZ, Solmate, ForgeStd)
├── test/ # Excluded from this PRD
├── README.md
└── .env.example
## 8. Documentation Strategy

1.  **README.md**: Project overview, setup, deployment for the carbon stack.
2.  **NatSpec Comments**: Comprehensive // comments within Solidity code.
3.  **Architecture Diagram**: Separate visual aid showing carbon stack interactions.
4.  **This PRD**: Primary implementation specification for the carbon stack.

## 9. Implementation Guidelines

* **Clarity for AI:** Use descriptive names, explicit comments, clear logic.
* **Security:** Prioritize access control (ensure roles are correctly assigned and managed), prevent replay attacks (`processedBatchHashes`), use ReentrancyGuards on reward claims/deposits.
* **Gas Efficiency:** `submitEnergyDataBatch` processes potentially large arrays. Optimize loops, storage writes (use mappings efficiently), and calculations. Consider if contribution updates need to happen per-entry or can be aggregated per batch per operator. Ensure reward calculation logic avoids O(N) loops where N is the number of nodes.
* **Data Integrity:** Rely on the trusted `DATA_SUBMITTER_ROLE` for data validity in MVP. Future versions might incorporate on-chain signature verification or ZK proofs.
* **Events:** Emit detailed events for data submission, credit minting, reward deposits, contribution updates, and claims.
* **Upgradeability:** Implement UUPS correctly. Pay close attention to storage layout for reward calculation logic if it changes significantly.
