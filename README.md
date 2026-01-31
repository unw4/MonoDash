# MonoDash

A decentralized micro-event betting platform built on Monad testnet. Leverages Monad's 400ms block time and parallel transaction execution to deliver ultra-fast betting experiences.

## Features

- **Micro-events:** 30-60 second betting windows for real-time action
- **Sharded storage:** 16 shards with 93.75% parallel safety — concurrent bettors almost never block each other
- **Session keys:** Gasless betting UX without wallet popups
- **Aura AI verification:** Events verified via ECDSA-based AI attestations
- **Pyth oracle integration:** Real-time price feeds
- **Proportional payouts:** Winners split the pool by stake ratio (2% house fee)

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, anvil, cast)
- Python 3 (HTTP server for frontend)
- MetaMask or compatible wallet

## Installation

```bash
git clone https://github.com/unw4/MonoDash.git
cd MonoDash
forge install
```

## Running

### Frontend

```bash
chmod +x start.sh
./start.sh
```

Open `http://localhost:8080` in your browser.

### MetaMask Setup

| Field        | Value                              |
|--------------|------------------------------------|
| Network Name | Monad Testnet                      |
| RPC URL      | https://testnet-rpc.monad.xyz      |
| Chain ID     | 10143                              |
| Currency     | MON                                |
| Explorer     | https://testnet.monadscan.com      |

### Contract Deployment

Contracts are already deployed on Monad testnet. To redeploy:

```bash
# Create .env file
cp .env.example .env
# Fill in DEPLOYER_PRIVATE_KEY

# Deploy
source .env && forge script script/Deploy.s.sol --rpc-url $MONAD_RPC_URL --broadcast --legacy
```

### Local Testing (Anvil)

```bash
anvil
# In another terminal:
forge script script/LocalDeploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

## Contract Architecture

```
src/
├── core/
│   ├── EventManager.sol          # Event lifecycle (OPEN -> LOCKED -> SETTLED/VOIDED)
│   ├── BettingEngine.sol         # Sharded betting engine (16 shards, parallel writes)
│   ├── SettlementProcessor.sol   # Batch settlement orchestrator
│   └── UserVault.sol             # Per-user balance management
├── oracle/
│   ├── PythAdapter.sol           # Pyth Network oracle wrapper
│   └── AuraVerifier.sol          # AI attestation verification (ECDSA)
├── account/
│   ├── SessionKeyManager.sol     # Ephemeral session key authorization
│   └── DelegatedSigner.sol       # EIP-712 signature verification
├── libraries/
│   ├── MicroEventLib.sol         # Event ID generation, window validation
│   ├── BetLib.sol                # Bet validation, payout calculation
│   └── ShardLib.sol              # Storage sharding logic
└── interfaces/                   # 6 interface files
```

### Deployed Contracts (Monad Testnet)

| Contract             | Address                                      |
|----------------------|----------------------------------------------|
| AuraVerifier         | `0x758658c989648597db25630264a7b2b58d849099` |
| PythAdapter          | `0x85348658d774e024b4ae31e16e0da9a3e16703a1` |
| UserVault            | `0x472d1f17e59a952f2856bd7c5dfa48fc017746bd` |
| DelegatedSigner      | `0xeee18e9c6f8f6d5999053c22a2919bed74689c9f` |
| EventManager         | `0x794fdb692cc382643a2da6d3036ba1b17beaec98` |
| BettingEngine        | `0x3605249370edaca26da4f8f8d6eee9bb63a45ed9` |
| SessionKeyManager    | `0x21da3d98da6e97ff10d0c493feb97c697832daa6` |
| SettlementProcessor  | `0x5cdeddbc014c919a16da9f6061f92fca8e1cc8ca` |

## Parallel Execution Design

MonoDash's sharded state architecture ensures concurrent bettors never block each other:

```
userBets[user][eventId]                    -> Per-user slot (PARALLEL SAFE)
poolShards[eventId][outcome][shard]        -> 16 independent shards (93.75% parallel)
UserVault._balances[user]                  -> Per-user slot (PARALLEL SAFE)
```

Shard index is derived from the last 4 bits of the user's address (`uint8(uint160(user) & 0x0F)`), creating 16 independent write slots.

## Tests

```bash
# All tests
forge test

# Specific contract
forge test --match-contract EventManager

# Verbose output
forge test -vvv

# Gas snapshot
forge snapshot
```

## Project Structure

```
MonoDash/
├── src/                    # Solidity contracts
├── test/
│   ├── unit/               # Unit tests (5 files)
│   ├── integration/        # Integration test
│   └── mocks/              # Mock contracts
├── script/
│   ├── Deploy.s.sol        # Monad testnet deployment
│   └── LocalDeploy.s.sol   # Local Anvil deployment
├── frontend/
│   ├── index.html          # Single-page app (ethers.js v6)
│   └── monodashlogo.png    # Logo
├── foundry.toml            # Foundry configuration
└── start.sh                # Frontend launch script
```

## Usage Flow

1. Launch the frontend with `start.sh`
2. Connect MetaMask to Monad Testnet
3. Get test MON from faucet
4. Connect wallet via the UI
5. Deposit MON
6. Create an event or bet on an existing one
7. Wait for settlement after the event closes
8. Claim your winnings

## Technical Details

| Parameter         | Value                |
|-------------------|----------------------|
| Solidity          | 0.8.24 (Cancun EVM) |
| Betting window    | 30-60 seconds        |
| Outcomes          | 2-10                 |
| Min bet           | 0.001 MON            |
| Max bet           | 100 MON              |
| House fee         | 2% (200 bps)         |
| Shard count       | 16                   |
| Parallel rate     | 93.75%               |

## License

MIT
