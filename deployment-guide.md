# Ether.fi Protocol Deployment Guide

This guide provides step-by-step instructions for deploying the ether.fi Ethereum staking protocol to a testnet (like Goerli or Holesky) or a local development environment (like Anvil).

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Environment Setup](#environment-setup)
3. [Deployment Process](#deployment-process)
   - [Phase 1: Core Protocol Deployment](#phase-1-core-protocol-deployment)
   - [Phase 1.5: Additional Protocol Components](#phase-15-additional-protocol-components)
   - [Phase 2: Oracle and Admin Components](#phase-2-oracle-and-admin-components)
4. [Post-Deployment Configuration](#post-deployment-configuration)
5. [Deployment to Local Anvil Instance](#deployment-to-local-anvil-instance)
6. [Contract Verification](#contract-verification)
7. [Troubleshooting](#troubleshooting)

## Prerequisites

Before starting deployment, ensure you have the following installed:

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install Node.js and Yarn
# Node.js: https://nodejs.org/
npm install -g yarn

# Clone the repository
git clone <repository-url>
cd ether-fi-smart-contracts

# Install dependencies
git submodule update --init --recursive

# Install additional utilities
# For Mac
brew install jq
# For Windows
chocolatey install jq

# Mac only: Install Xcode Command Line Tools
xcode-select --install
```

## Environment Setup

1. **Create and configure environment variables**:

   Copy the example environment file and configure it with your specific values:

   ```bash
   cp .env.example .env
   ```

   Edit the `.env` file with the following configuration:

   ```properties
   # RPC URLs - Choose the appropriate one for your target network
   GOERLI_RPC_URL=https://goerli.infura.io/v3/YOUR_API_KEY
   MAINNET_RPC_URL=https://eth-mainnet.alchemyapi.io/v2/YOUR_API_KEY
   TESTNET_RPC_URL=https://ethereum-holesky-rpc.publicnode.com
   HOLESKY_RPC_URL=https://ethereum-holesky-rpc.publicnode.com
   
   # Deployment Account (use test account for testnet deployments)
   PRIVATE_KEY=YOUR_PRIVATE_KEY
   DEPLOYER=YOUR_DEPLOYER_ADDRESS
   
   # API Keys
   ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY
   
   # Oracle Configuration
   ORACLE_ADMIN_ADDRESS=YOUR_ORACLE_ADMIN_ADDRESS
   
   # Protocol Configuration
   BEACON_GENESIS_TIME=1695902400  # Holesky genesis time, change for other networks
   INITIAL_HASH=0x0000000000000000000000000000000000000000000000000000000000000000
   BASE_URI=https://your-api.example.com/metadata/
   ```

2. **Load environment variables**:

   ```bash
   source .env
   ```

## Deployment Process

The deployment is structured in three main phases. Follow these steps for a complete deployment:

### Phase 1: Core Protocol Deployment

Phase 1 deploys the core contracts including Node Operator Manager, Auction Manager, Staking Manager, EtherFi Nodes Manager, Protocol Revenue Manager, EtherFi Node, Treasury, TNFT, and BNFT.

1. **Compile the contracts**:

   ```bash
   forge build
   ```

2. **Deploy Phase 1 contracts**:

   ```bash
   make deploy-phase-1
   ```

   This will:
   - Deploy implementation contracts
   - Initialize UUPS proxies pointing to the implementations
   - Set up contract dependencies
   - Extract ABIs for future interactions

3. **Set up Merkle roots** (required after deployment):

   Generate Merkle trees for Node Operators and whitelisted stakers:

   ```bash
   # Generate Merkle tree for Node Operators
   node script/Merkletree.js nodeOperators

   # Generate Merkle tree for whitelisted stakers
   node script/Merkletree.js whitelistedStakers

   # Update Merkle roots in their respective contracts
   # You'll need separate scripts or contract calls to update the roots
   ```

### Phase 1.5: Additional Protocol Components

Phase 1.5 deploys additional core contracts like EETH, Liquidity Pool, Membership Manager, and WeETH:

1. **Deploy Phase 1.5 contracts**:

   ```bash
   # For testnet
   make deploy-goerli-phase-1.5
   
   # For mainnet
   make deploy-mainnet-phase-1.5
   ```

### Phase 2: Oracle and Admin Components

Phase 2 deploys the Oracle, Admin, and WithdrawRequestNFT contracts which are essential for protocol governance and withdrawals:

1. **Deploy Phase 2 contracts**:

   Create a custom command or use the Foundry script directly:

   ```bash
   # Using Foundry script directly
   forge script script/deploys/DeployPhaseTwo.s.sol:DeployPhaseTwoScript --rpc-url ${TESTNET_RPC_URL} --broadcast --verify -vvvv --slow
   ```

   This will:
   - Deploy the WithdrawRequestNFT contract
   - Deploy the EtherFiOracle contract
   - Deploy the EtherFiAdmin contract
   - Configure connections between contracts
   - Set up committee members for the Oracle

## Post-Deployment Configuration

After deployment, several configuration steps are needed:

1. **Update admin addresses**:

   ```bash
   # Set admin addresses for security and governance
   forge script script/UpdateAdmin.s.sol:UpdateAdminScript --rpc-url ${TESTNET_RPC_URL} --broadcast --verify -vvvv --slow
   ```

2. **Set up contract parameters**:

   ```bash
   # Configure protocol fees, node operator requirements, auction parameters, etc.
   # This may require custom scripts depending on your specific configuration needs
   ```

3. **Optional components deployment**:

   ```bash
   # Deploy TVL Oracle
   make deploy-goerli-tvlOracle
   
   # Deploy Loyalty Points Market
   make deploy-goerli-lpaPoints
   
   # Deploy Early Adopter Pool
   make deploy-goerli-early-reward-pool
   ```

## Deployment to Local Anvil Instance

For testing locally, you can deploy to an Anvil instance:

1. **Start an Anvil instance**:

   ```bash
   anvil --fork-url ${MAINNET_RPC_URL} --fork-block-number 17000000
   ```

2. **Deploy to Anvil** (in a separate terminal):

   Modify the scripts to work with Anvil's chain ID (31337) and use the local RPC URL:

   ```bash
   # Phase 1
   forge script script/deploys/DeployPhaseOne.s.sol:DeployPhaseOne --rpc-url http://localhost:8545 --broadcast -vvvv
   
   # Phase 1.5
   forge script script/deploys/DeployPhaseOnePointFive.s.sol:DeployPhaseOnePointFiveScript --rpc-url http://localhost:8545 --broadcast -vvvv
   
   # Phase 2
   forge script script/deploys/DeployPhaseTwo.s.sol:DeployPhaseTwoScript --rpc-url http://localhost:8545 --broadcast -vvvv
   ```

3. **Run test transactions**:

   ```bash
   # Example: test happy path flow
   node happyPath.js --network anvil
   ```

## Contract Verification

Contract verification happens automatically with the `--verify` flag, but you may need to verify contracts manually if verification fails:

```bash
forge verify-contract <deployed-contract-address> <contract-name> --etherscan-api-key ${ETHERSCAN_API_KEY} --chain <chain-id>
```

## Troubleshooting

If you encounter issues during deployment:

1. **Network connection issues**:
   - Ensure your RPC URL is correct and accessible
   - Try using a different RPC provider

2. **Gas-related errors**:
   - Adjust gas settings in your Foundry config
   - For Anvil, you may need to increase the gas limit

3. **Compiler version conflicts**:
   ```bash
   # Install specific Solidity version if needed
   svm install "0.8.13"
   ```

4. **Deployment transaction failures**:
   - Check transaction logs with the `-vvvv` flag
   - Ensure your account has sufficient ETH

5. **Address Provider issues**:
   - Check if the contract registry is properly configured
   - Verify that contract addresses are correctly registered

6. **Oracle configuration issues**:
   - Verify the correct beacon chain genesis time is set
   - Confirm committee members are properly added

---

This guide covers deploying the ether.fi protocol on testnet or local Anvil instance. For production mainnet deployments, additional security measures should be implemented, including using multisig wallets for administration and conducting comprehensive security audits.

For more detailed information, refer to the protocol documentation or reach out to the ether.fi team.
