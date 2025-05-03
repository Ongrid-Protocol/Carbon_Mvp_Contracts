# OnGrid Protocol Carbon Credit System Integration Guide

## Overview

This guide provides detailed instructions for integrating the OnGrid Protocol Carbon Credit System into a Rust-based networking stack. The system consists of several smart contracts that work together to track energy generation, mint carbon credits, and distribute rewards.

## System Components

1. **EnergyDataBridge**: Processes verified energy data to mint carbon credits and update node contributions
2. **CarbonCreditToken**: ERC20 token representing carbon credits (tonnes of CO2e avoided)
3. **RewardDistributor**: Distributes rewards to node operators based on their contributions
4. **CarbonCreditExchange**: Enables exchange of carbon credits for USDC with a protocol fee

## Contract Interaction Flow

```
                      ┌───────────────────┐
                      │                   │
                      │  Energy Data P2P  │
                      │     Network       │
                      │                   │
                      └─────────┬─────────┘
                                │
                                ▼
                      ┌───────────────────┐
                      │                   │
                      │  EnergyDataBridge │
                      │                   │
                      └─────────┬─────────┘
                                │
                                ▼
           ┌───────────────────┴───────────────────┐
           │                                       │
           ▼                                       ▼
┌───────────────────┐                  ┌───────────────────┐
│                   │                  │                   │
│ CarbonCreditToken │                  │ RewardDistributor │
│                   │                  │                   │
└─────────┬─────────┘                  └───────────────────┘
          │
          ▼
┌───────────────────┐
│                   │
│CarbonCreditExchange│
│                   │
└───────────────────┘
```

## Integration Steps

### 1. Setting Up Rust Dependencies

Add these to your Cargo.toml:

```toml
[dependencies]
ethers = { version = "2.0", features = ["abigen", "ws"] }
tokio = { version = "1.32", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
dotenv = "0.15"
```

### 2. Environment Setup

Create a `.env` file to store contract addresses and private keys:

```
RPC_URL=https://rpc-endpoint.example.com
PRIVATE_KEY=your_private_key_here
BRIDGE_ADDRESS=0x...
CARBON_TOKEN_ADDRESS=0x...
REWARD_DISTRIBUTOR_ADDRESS=0x...
EXCHANGE_ADDRESS=0x...
```

### 3. Core Integration Code Structure

```rust
use ethers::{
    contract::Abigen,
    prelude::*,
    providers::{Http, Provider},
    signers::{LocalWallet, Signer},
};
use std::sync::Arc;
use std::env;
use dotenv::dotenv;

// Load ABIs and generate Rust contract bindings
abigen!(
    EnergyDataBridge,
    "./abis/EnergyDataBridge.json",
    event_derives(serde::Deserialize, serde::Serialize)
);

abigen!(
    CarbonCreditToken,
    "./abis/CarbonCreditToken.json",
    event_derives(serde::Deserialize, serde::Serialize)
);

abigen!(
    RewardDistributor,
    "./abis/RewardDistributor.json",
    event_derives(serde::Deserialize, serde::Serialize)
);

abigen!(
    CarbonCreditExchange,
    "./abis/CarbonCreditExchange.json",
    event_derives(serde::Deserialize, serde::Serialize)
);

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    dotenv().ok();
    
    // Connect to the blockchain
    let rpc_url = env::var("RPC_URL")?;
    let provider = Provider::<Http>::try_from(rpc_url)?;
    
    // Set up wallet
    let private_key = env::var("PRIVATE_KEY")?;
    let wallet = private_key.parse::<LocalWallet>()?;
    let client = SignerMiddleware::new(provider, wallet);
    let client = Arc::new(client);
    
    // Initialize contract instances
    let bridge_address = env::var("BRIDGE_ADDRESS")?.parse::<Address>()?;
    let bridge = EnergyDataBridge::new(bridge_address, client.clone());
    
    let token_address = env::var("CARBON_TOKEN_ADDRESS")?.parse::<Address>()?;
    let token = CarbonCreditToken::new(token_address, client.clone());
    
    let distributor_address = env::var("REWARD_DISTRIBUTOR_ADDRESS")?.parse::<Address>()?;
    let distributor = RewardDistributor::new(distributor_address, client.clone());
    
    let exchange_address = env::var("EXCHANGE_ADDRESS")?.parse::<Address>()?;
    let exchange = CarbonCreditExchange::new(exchange_address, client.clone());
    
    Ok(())
}
```

### 4. Detailed EnergyDataBridge Integration

The EnergyDataBridge is the most critical component for integration, as it processes energy data from the P2P network.

#### 4.1 Define Energy Data Structures

```rust
// Energy data structure matching Solidity struct
struct EnergyData {
    device_id: [u8; 32],
    node_operator_address: Address,
    energy_kwh: U256,
    timestamp: u64,
}

// P2P Consensus proof structure
struct P2PConsensusProof {
    consensus_round_id: [u8; 32],
    participating_node_count: U256,
    consensus_result_hash: [u8; 32],
    multi_signature: Vec<u8>,
}
```

#### 4.2 Submitting Energy Data Batches

```rust
async fn submit_energy_data_batch(
    bridge: &EnergyDataBridge<SignerMiddleware<Provider<Http>, LocalWallet>>,
    data_batch: Vec<EnergyData>,
    consensus_proof: P2PConsensusProof,
) -> Result<TransactionReceipt, Box<dyn std::error::Error>> {
    // Convert Rust structures to contract-compatible types
    let contract_data_batch: Vec<(
        [u8; 32],
        Address,
        U256,
        u64,
    )> = data_batch
        .iter()
        .map(|data| (
            data.device_id,
            data.node_operator_address,
            data.energy_kwh,
            data.timestamp,
        ))
        .collect();

    let contract_consensus_proof = (
        consensus_proof.consensus_round_id,
        consensus_proof.participating_node_count,
        consensus_proof.consensus_result_hash,
        consensus_proof.multi_signature,
    );

    // Submit batch to the contract
    let tx = bridge.submit_energy_data_batch(contract_data_batch, contract_consensus_proof);
    let pending_tx = tx.send().await?;
    let receipt = pending_tx.await?;
    
    Ok(receipt.unwrap())
}
```

#### 4.3 Processing Batches After Challenge Period

```rust
async fn process_batch(
    bridge: &EnergyDataBridge<SignerMiddleware<Provider<Http>, LocalWallet>>,
    batch_hash: [u8; 32],
) -> Result<TransactionReceipt, Box<dyn std::error::Error>> {
    let tx = bridge.process_batch(batch_hash);
    let pending_tx = tx.send().await?;
    let receipt = pending_tx.await?;
    
    Ok(receipt.unwrap())
}
```

#### 4.4 Node Registration

```rust
async fn register_node(
    bridge: &EnergyDataBridge<SignerMiddleware<Provider<Http>, LocalWallet>>,
    peer_id: [u8; 32],
    operator: Address,
) -> Result<TransactionReceipt, Box<dyn std::error::Error>> {
    let tx = bridge.register_node(peer_id, operator);
    let pending_tx = tx.send().await?;
    let receipt = pending_tx.await?;
    
    Ok(receipt.unwrap())
}
```

### 5. P2P Network Integration with EnergyDataBridge

#### 5.1 Consensus Management

```rust
// Collect signatures from participating nodes
async fn collect_signatures(
    data_hash: [u8; 32],
    nodes: Vec<Address>,
) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
    // Implementation depends on your P2P network
    // This should collect and aggregate signatures from nodes
    
    Ok(Vec::new()) // Placeholder
}

// Generate consensus proof
async fn generate_consensus_proof(
    data_batch: &Vec<EnergyData>,
    participating_nodes: Vec<Address>,
) -> Result<P2PConsensusProof, Box<dyn std::error::Error>> {
    // Create a unique ID for this consensus round
    let consensus_round_id = [0u8; 32]; // Replace with proper ID generation
    
    // Hash the data batch
    let data_hash = keccak256(&data_batch); // Implement proper serialization & hashing
    
    // Collect signatures from nodes
    let multi_signature = collect_signatures(data_hash, participating_nodes).await?;
    
    Ok(P2PConsensusProof {
        consensus_round_id,
        participating_node_count: U256::from(participating_nodes.len()),
        consensus_result_hash: data_hash,
        multi_signature,
    })
}
```

#### 5.2 Complete Flow for Energy Data Submission

```rust
async fn handle_energy_data_from_p2p_network(
    bridge: &EnergyDataBridge<SignerMiddleware<Provider<Http>, LocalWallet>>,
    raw_data: Vec<RawEnergyData>, // Your P2P network data format
    participating_nodes: Vec<Address>,
) -> Result<(), Box<dyn std::error::Error>> {
    // 1. Format data for blockchain submission
    let data_batch: Vec<EnergyData> = raw_data
        .into_iter()
        .map(|raw| {
            // Convert your raw data format to EnergyData structure
            EnergyData {
                device_id: raw.device_id,
                node_operator_address: raw.operator_address,
                energy_kwh: U256::from(raw.energy_kwh),
                timestamp: raw.timestamp,
            }
        })
        .collect();
    
    // 2. Generate consensus proof
    let consensus_proof = generate_consensus_proof(&data_batch, participating_nodes).await?;
    
    // 3. Submit batch to the bridge contract
    let receipt = submit_energy_data_batch(bridge, data_batch, consensus_proof).await?;
    
    // 4. Store batch hash for later processing
    let events = receipt.logs
        .iter()
        .filter_map(|log| bridge.decode_event::<EnergyDataSubmittedFilter>("EnergyDataSubmitted", log))
        .collect::<Vec<_>>();
    
    if let Some(Ok(event)) = events.first() {
        let batch_hash = event.0.batch_hash;
        let process_after = event.0.process_after_timestamp;
        
        // Store for processing after challenge period
        store_batch_for_processing(batch_hash, process_after);
    }
    
    Ok(())
}

// Example placeholder function to store batch info
fn store_batch_for_processing(batch_hash: [u8; 32], process_after: U256) {
    // Implement storage based on your system
}
```

### 6. Batch Processing Job

```rust
async fn process_pending_batches(
    bridge: &EnergyDataBridge<SignerMiddleware<Provider<Http>, LocalWallet>>,
) -> Result<(), Box<dyn std::error::Error>> {
    // Get pending batches that are ready for processing
    let pending_batches = get_pending_batches_ready_for_processing();
    
    for batch_hash in pending_batches {
        match process_batch(bridge, batch_hash).await {
            Ok(receipt) => {
                // Handle successful processing
                let events = receipt.logs
                    .iter()
                    .filter_map(|log| bridge.decode_event::<EnergyDataProcessedFilter>("EnergyDataProcessed", log))
                    .collect::<Vec<_>>();
                
                if let Some(Ok(event)) = events.first() {
                    let total_credits_minted = event.0.total_credits_minted;
                    let entries_processed = event.0.entries_processed;
                    
                    // Log or store information about processed batch
                    log_processed_batch(batch_hash, total_credits_minted, entries_processed);
                }
                
                // Mark batch as processed
                mark_batch_processed(batch_hash);
            },
            Err(e) => {
                // Handle errors (retry logic, logging, etc.)
                log_error(batch_hash, e);
            }
        }
    }
    
    Ok(())
}

// Example placeholder functions
fn get_pending_batches_ready_for_processing() -> Vec<[u8; 32]> {
    // Implementation depends on your storage system
    Vec::new()
}

fn mark_batch_processed(batch_hash: [u8; 32]) {
    // Implementation depends on your storage system
}

fn log_processed_batch(batch_hash: [u8; 32], total_credits_minted: U256, entries_processed: U256) {
    // Implementation depends on your logging system
}

fn log_error(batch_hash: [u8; 32], error: Box<dyn std::error::Error>) {
    // Implementation depends on your logging system
}
```

### 7. Integration with Other Contracts

#### 7.1 Monitoring RewardDistributor

```rust
async fn monitor_reward_claims(
    reward_distributor: &RewardDistributor<SignerMiddleware<Provider<Http>, LocalWallet>>,
) -> Result<(), Box<dyn std::error::Error>> {
    // Set up event listener for RewardsClaimed events
    let events = reward_distributor.events().from_block(0u64);
    let mut stream = events.stream().await?;
    
    while let Some(Ok(event)) = stream.next().await {
        match event {
            RewardDistributorEvents::RewardsClaimedFilter(claim) => {
                // Process reward claim
                let operator = claim.operator;
                let amount = claim.amount;
                
                // Update your system
                log_reward_claim(operator, amount);
            },
            _ => {}
        }
    }
    
    Ok(())
}
```

#### 7.2 CarbonCreditExchange Monitoring

```rust
async fn monitor_credit_exchanges(
    exchange: &CarbonCreditExchange<SignerMiddleware<Provider<Http>, LocalWallet>>,
) -> Result<(), Box<dyn std::error::Error>> {
    // Set up event listener for CreditsExchanged events
    let events = exchange.events().from_block(0u64);
    let mut stream = events.stream().await?;
    
    while let Some(Ok(event)) = stream.next().await {
        match event {
            CarbonCreditExchangeEvents::CreditsExchangedFilter(exchange_event) => {
                // Process credit exchange
                let user = exchange_event.user;
                let credit_amount = exchange_event.credit_amount;
                let usdc_amount = exchange_event.usdc_amount;
                let fee_amount = exchange_event.fee_amount;
                
                // Update your system
                log_credit_exchange(user, credit_amount, usdc_amount, fee_amount);
            },
            _ => {}
        }
    }
    
    Ok(())
}
```

### 8. Error Handling

```rust
// Define custom errors for your integration
enum IntegrationError {
    ContractError(String),
    NetworkError(String),
    ConsensusError(String),
    DataFormatError(String),
}

impl From<ContractError<Provider<Http>>> for IntegrationError {
    fn from(error: ContractError<Provider<Http>>) -> Self {
        IntegrationError::ContractError(format!("{:?}", error))
    }
}

// Add error handling to your functions
async fn safe_submit_batch(
    bridge: &EnergyDataBridge<SignerMiddleware<Provider<Http>, LocalWallet>>,
    data_batch: Vec<EnergyData>,
    consensus_proof: P2PConsensusProof,
    retry_count: u8,
) -> Result<TransactionReceipt, IntegrationError> {
    let mut attempts = 0;
    
    while attempts < retry_count {
        match submit_energy_data_batch(bridge, data_batch.clone(), consensus_proof.clone()).await {
            Ok(receipt) => return Ok(receipt),
            Err(e) => {
                // Check if error is temporary (gas price, nonce, etc.)
                if is_temporary_error(&e) {
                    attempts += 1;
                    tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
                    continue;
                }
                
                // Permanent error
                return Err(IntegrationError::ContractError(format!("{:?}", e)));
            }
        }
    }
    
    Err(IntegrationError::NetworkError("Max retry count exceeded".to_string()))
}

fn is_temporary_error(error: &Box<dyn std::error::Error>) -> bool {
    // Implement logic to identify temporary errors
    error.to_string().contains("nonce") || error.to_string().contains("gas")
}
```

### 9. Testing and Verification

```rust
async fn verify_bridge_configuration(
    bridge: &EnergyDataBridge<SignerMiddleware<Provider<Http>, LocalWallet>>,
) -> Result<bool, Box<dyn std::error::Error>> {
    // Check key parameters
    let token_address = bridge.carbon_credit_token().call().await?;
    let distributor_address = bridge.reward_distributor().call().await?;
    let emission_factor = bridge.emission_factor().call().await?;
    let req_consensus_nodes = bridge.required_consensus_nodes().call().await?;
    
    println!("Bridge Configuration:");
    println!("CarbonCreditToken: {:?}", token_address);
    println!("RewardDistributor: {:?}", distributor_address);
    println!("Emission Factor: {:?}", emission_factor);
    println!("Required Consensus Nodes: {:?}", req_consensus_nodes);
    
    // Verify the values match expected configuration
    let expected_token = env::var("CARBON_TOKEN_ADDRESS")?.parse::<Address>()?;
    let expected_distributor = env::var("REWARD_DISTRIBUTOR_ADDRESS")?.parse::<Address>()?;
    
    Ok(token_address == expected_token && distributor_address == expected_distributor)
}
```

## Contract Function Inputs/Outputs and Events

### EnergyDataBridge

#### Key Functions

1. **submitEnergyDataBatch**
   - **Inputs**: 
     - `dataBatch`: Array of `EnergyData` structs (deviceId, nodeOperatorAddress, energyKWh, timestamp)
     - `consensusProof`: P2P consensus proof (consensusRoundId, participatingNodeCount, consensusResultHash, multiSignature)
   - **Events Emitted**: 
     - `EnergyDataSubmitted(bytes32 batchHash, uint256 entriesSubmitted, uint256 processAfterTimestamp)`
   - **Expected Behavior**: Stores batch data for later processing after the challenge period

2. **processBatch**
   - **Inputs**: 
     - `batchHash`: bytes32 hash of the batch to process
   - **Events Emitted**: 
     - `EnergyDataProcessed(bytes32 batchHash, uint256 totalCreditsMinted, uint256 entriesProcessed)`
   - **Expected Behavior**: Mints carbon credits to treasury and updates node contributions in RewardDistributor

3. **registerNode**
   - **Inputs**: 
     - `peerId`: bytes32 identifier in the P2P network
     - `operator`: address of the node operator
   - **Events Emitted**: 
     - `NodeRegistered(bytes32 peerId, address operator)`
   - **Expected Behavior**: Registers a node in the system for participation

4. **challengeBatch**
   - **Inputs**: 
     - `batchHash`: bytes32 hash of the batch to challenge
     - `reason`: string explaining the reason for challenge
   - **Events Emitted**: 
     - `BatchChallenged(bytes32 batchHash, address challenger, string reason)`
   - **Expected Behavior**: Creates a challenge against a submitted batch

### CarbonCreditToken

#### Key Functions

1. **mintToTreasury**
   - **Inputs**: 
     - `amount`: uint256 amount of tokens to mint
   - **Events Emitted**: 
     - Standard ERC20 `Transfer` event from zero address to treasury
   - **Expected Behavior**: Mints tokens to the protocol treasury

2. **transferFromTreasury**
   - **Inputs**: 
     - `to`: address of the recipient
     - `amount`: uint256 amount to transfer
   - **Events Emitted**: 
     - Standard ERC20 `Transfer` event
     - `TreasuryTransfer(address to, uint256 amount)`
   - **Expected Behavior**: Transfers tokens from treasury to recipient

3. **retireFromTreasury**
   - **Inputs**: 
     - `amount`: uint256 amount to retire (burn)
     - `reason`: string explaining the reason for retirement
   - **Events Emitted**: 
     - Standard ERC20 `Transfer` event to zero address
     - `TreasuryRetirement(uint256 amount, string reason)`
   - **Expected Behavior**: Burns tokens from treasury with a recorded reason

### RewardDistributor

#### Key Functions

1. **updateNodeContribution**
   - **Inputs**: 
     - `operator`: address of the node operator
     - `contributionDelta`: uint256 change in contribution score
     - `timestamp`: uint64 timestamp associated with this update
   - **Events Emitted**: 
     - `NodeContributionUpdated(address operator, uint256 newScore, uint64 timestamp)`
   - **Expected Behavior**: Updates the operator's contribution score and reward debt

2. **depositRewards**
   - **Inputs**: 
     - `amount`: uint256 amount of reward tokens to deposit
   - **Events Emitted**: 
     - `RewardsDeposited(address depositor, uint256 amount)`
   - **Expected Behavior**: Transfers reward tokens to the contract

3. **claimRewards**
   - **Inputs**: None (caller is msg.sender)
   - **Events Emitted**: 
     - `RewardsClaimed(address operator, uint256 amount)`
   - **Expected Behavior**: Transfers accrued rewards to the operator

4. **claimableRewards**
   - **Inputs**: 
     - `operator`: address of the node operator
   - **Outputs**: 
     - `uint256`: Amount of reward tokens claimable
   - **Expected Behavior**: Calculates pending rewards based on contribution score and time

### CarbonCreditExchange

#### Key Functions

1. **exchangeCreditsForUSDC**
   - **Inputs**: 
     - `creditAmount`: uint256 amount of carbon credits to exchange
   - **Events Emitted**: 
     - `CreditsExchanged(address user, uint256 creditAmount, uint256 usdcAmount, uint256 feeAmount)`
     - `RewardsPoolFunded(uint256 amount)` if rewards are funded
   - **Expected Behavior**: Exchanges carbon credits for USDC, applying protocol fee and funding rewards

2. **setExchangeRate**
   - **Inputs**: 
     - `newRate`: uint256 new exchange rate (scaled by 1e6)
   - **Events Emitted**: 
     - `ExchangeRateSet(uint256 oldRate, uint256 newRate)`
   - **Expected Behavior**: Updates the exchange rate used for credit/USDC conversion

3. **setProtocolFee**
   - **Inputs**: 
     - `newFeePercentage`: uint256 new fee percentage (scaled by 1e6)
   - **Events Emitted**: 
     - `ProtocolFeeSet(uint256 oldFee, uint256 newFee)`
   - **Expected Behavior**: Updates the fee percentage applied on exchanges

## User Flows and Expected Behavior

### Energy Data Collection & Carbon Credit Minting Flow

1. **P2P Network Data Collection**
   - Energy data is collected from devices in the network
   - Data is aggregated and validated by P2P nodes
   - P2P consensus is reached through multi-signature mechanism

2. **Data Submission to Blockchain**
   - The aggregated data is formatted as an array of `EnergyData` structs
   - A consensus proof is generated with signatures from participating nodes
   - Data is submitted to `EnergyDataBridge.submitEnergyDataBatch()`
   - An `EnergyDataSubmitted` event is emitted with the batch hash and processing time

3. **Challenge Period**
   - The submitted batch enters a challenge period (configurable duration)
   - During this period, any participant can call `challengeBatch()` with a reason
   - If challenged, an admin must resolve the challenge with `resolveChallenge()`

4. **Batch Processing**
   - After the challenge period, `processBatch()` can be called with the batch hash
   - The contract verifies no unresolved challenges exist
   - For each valid entry in the batch:
     - Carbon credits are calculated based on the emission factor
     - Tokens are minted to the treasury via `CarbonCreditToken.mintToTreasury()`
     - Node contributions are updated via `RewardDistributor.updateNodeContribution()`
   - An `EnergyDataProcessed` event is emitted with credits minted and entries processed

### Node Operator Reward Flow

1. **Contribution Updates**
   - As energy data is processed, node operators' contributions are updated
   - Each contribution update increases their share in the reward pool
   - The `NodeContributionUpdated` event is emitted with new scores

2. **Reward Accrual**
   - Rewards accrue over time based on contribution scores
   - When the exchange processes carbon credit trades, a portion of fees goes to rewards
   - Fees are sent to the RewardDistributor via `depositRewards()`

3. **Reward Claiming**
   - Node operators can check claimable rewards via `claimableRewards()`
   - They can claim rewards by calling `claimRewards()`
   - Upon claiming, a `RewardsClaimed` event is emitted

### Carbon Credit Exchange Flow

1. **Credit Exchange**
   - Users with carbon credits call `exchangeCreditsForUSDC()` with an amount
   - The contract calculates USDC amount based on the exchange rate
   - Protocol fee is deducted from the USDC amount
   - A portion of the fee is sent to the reward distributor
   - User receives net USDC amount after fees
   - A `CreditsExchanged` event is emitted with transaction details

2. **Exchange Parameter Updates**
   - Admin can update exchange rate via `setExchangeRate()`
   - Admin can update fee percentage via `setProtocolFee()`
   - Admin can update reward percentage via `setRewardDistributorPercentage()`
   - Each parameter update emits a corresponding event

## Important Implementation Notes

1. **Consensus Mechanism**
   - The P2P network must implement a robust consensus mechanism
   - Signatures from participating nodes must be collected and aggregated
   - The number of signatures must meet the `requiredConsensusNodes` threshold

2. **Batch Processing Timing**
   - You must store batch hashes and their processing times
   - Implement a background job to process batches after their challenge period
   - Track processing status to avoid duplicate processing

3. **Error Handling**
   - Implement proper error handling for all contract calls
   - Use retry mechanisms for temporary failures (gas price issues, etc.)
   - Log all errors for troubleshooting

4. **Event Monitoring**
   - Set up listeners for all relevant contract events
   - Update your system state based on these events
   - Implement proper error handling for event processing

5. **Security Considerations**
   - Protect private keys used for contract interactions
   - Validate all data before submitting to the blockchain
   - Implement proper access controls for administrative functions 