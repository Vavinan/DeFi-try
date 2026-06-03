# Foundry DeFi Stablecoin

This project is a decentralized, exogenous, anchored (pegged), crypto-collateralized stablecoin system built with Foundry. It is part of the Cyfrin Foundry Solidity Course.

**Etherscan Links (Examples):**
- [DSCEngine](https://sepolia.etherscan.io/address/0x091ea0838ebd5b7dda2f2a641b068d6d59639b98#code)
- [Decentralized Stablecoin](https://sepolia.etherscan.io/address/0xf30021646269007b0bdc0763fd736c6380602f2f#code)

# About

This protocol aims to maintain a $1.00 peg through an algorithmic stability mechanism.

- **Collateral Type**: Exogenous (wETH and wBTC).
- **Minting**: Users can only mint the stablecoin by providing collateral (over-collateralized).
- **Stability Mechanism**: Algorithmic / Decentralized.
- **Price Feed**: Utilizes Chainlink Price Feeds to maintain the peg and calculate collateral values.

## Table of Contents
- [Getting Started](#getting-started)
  - [Requirements](#requirements)
  - [Quickstart](#quickstart)
- [Updates](#updates)
- [Usage](#usage)
  - [Start a local node](#start-a-local-node)
  - [Deploy](#deploy)
  - [Testing](#testing)
  - [Test Coverage](#test-coverage)
- [Deployment to a testnet or mainnet](#deployment-to-a-testnet-or-mainnet)
- [Scripts (Manual Interaction)](#scripts-manual-interaction)
- [Formatting](#formatting)
- [Slither](#slither)

# Getting Started

## Requirements

- **Git**: Installation Guide
- **Foundry**: Installation Guide
  - Run `curl -L https://foundry.paradigm.xyz | bash` followed by `foundryup`.

## Quickstart

```bash
git clone git@github.com:Vavinan/DeFi-try.git
cd DeFi-try
forge install
forge build
```

# Updates

- **OpenZeppelin Versioning**: The latest version of `openzeppelin-contracts` has changes in the `ERC20Mock` file. To ensure compatibility with the course logic, install version 4.8.3:
  ```bash
  forge install openzeppelin/openzeppelin-contracts@v4.8.3
  ```

# Usage

### Testing
Run the full test suite:
```shell
forge test
```

Run a specific test with high verbosity (useful for debugging traces):
```shell
forge test --match-test testName -vvv
```

### Formatting
Ensure the code adheres to the Solidity style guide:
```shell
forge fmt
```

### Gas Snapshots
Generate a gas usage report:
```shell
forge snapshot
```

### Local Node
Start a local Ethereum node (Anvil):
```shell
anvil
```

### Deployment
To run your deployment scripts (e.g., on a local or testnet environment):
```shell
forge script script/DeployDSC.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key> --broadcast
```
## Start a local node

```bash
make anvil
# OR
anvil
```

## Deploy

Defaults to the local Anvil node. Ensure Anvil is running in a separate terminal.

```bash
forge script script/DeployDSC.s.sol --rpc-url http://127.0.0.1:8545 --private-key <ANVIL_PRIVATE_KEY> --broadcast
```

## Testing

The project includes Unit tests and Fuzzing logic.

**Run all tests:**
```bash
forge test
```

**Run a specific test (e.g., Liquidation Bonus):**
```bash
forge test --match-test testLiquidatorReceivesBonusCollateral -vvv
```

### Test Coverage

Check how much of your code is covered by tests:
```bash
forge coverage
```

For a detailed coverage report:
```bash
forge coverage --report debug
```

# Deployment to a testnet or mainnet

1. **Setup Environment Variables**
   Create a `.env` file or export them in your terminal:
   - `SEPOLIA_RPC_URL`: Your Alchemy/Infura URL.
   - `PRIVATE_KEY`: Your wallet private key (Use a burner wallet for safety!).
   - `ETHERSCAN_API_KEY`: (Optional) For contract verification.

2. **Deploy to Sepolia**
   ```bash
   forge script script/DeployDSC.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
   ```

# Gas Estimation

Generate a gas usage snapshot:
```bash
forge snapshot
```
This creates a `.gas-snapshot` file containing the gas cost for every function.

# Formatting

To keep the codebase clean and compliant with the Solidity style guide:
```bash
forge fmt
```



# Thank you!

