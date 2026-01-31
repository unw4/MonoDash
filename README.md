====================================================================
                               MonoDash
====================================================================

MonoDash is a micro-event–based decentralized betting platform
running on the Monad testnet. It leverages Monad’s 400ms block time
and parallel transaction execution model to deliver an ultra-fast,
low-latency betting experience.

--------------------------------------------------------------------
FEATURES
--------------------------------------------------------------------

- Micro-events
  30–60 second betting windows

- Sharded storage
  16 shards with 93.75% parallel safety. Users betting at the same
  time operate almost fully in parallel.

- Session key support
  Gasless betting experience without wallet popups.

- Aura AI verification
  Events are verified using ECDSA-based AI attestations.

- Pyth oracle integration
  Real-time price feeds.

- Proportional payouts
  Winners share the pool based on stake ratio.
  House fee: 2%

--------------------------------------------------------------------
REQUIREMENTS
--------------------------------------------------------------------

- Foundry (forge, anvil, cast)
- Python 3 (frontend HTTP server)
- MetaMask or compatible wallet

--------------------------------------------------------------------
INSTALLATION
--------------------------------------------------------------------

git clone https://github.com/unw4/MonoDash.git
cd MonoDash
forge install

--------------------------------------------------------------------
RUNNING THE PROJECT
--------------------------------------------------------------------

Frontend:

chmod +x start.sh
./start.sh

Open the following URL in your browser:
http://localhost:8080

--------------------------------------------------------------------
METAMASK CONFIGURATION
--------------------------------------------------------------------

Network Name : Monad Testnet
RPC URL      : https://testnet-rpc.monad.xyz
Chain ID     : 10143
Currency     : MON
Explorer     : https://testnet.monadscan.com

--------------------------------------------------------------------
CONTRACT DEPLOYMENT
--------------------------------------------------------------------

Contracts are already deployed on the Monad testnet.

To redeploy:

cp .env.example .env
# Fill in DEPLOYER_PRIVATE_KEY

source .env && forge script script/Deploy.s.sol \
  --rpc-url $MONAD_RPC_URL --broadcast --legacy

--------------------------------------------------------------------
LOCAL TESTING (ANVIL)
--------------------------------------------------------------------

anvil

In another terminal:

forge script script/LocalDeploy.s.sol \
  --rpc-url http://localhost:8545 --broadcast

--------------------------------------------------------------------
CONTRACT ARCHITECTURE
--------------------------------------------------------------------

src/
  core/
    EventManager.sol
      - Event lifecycle (OPEN -> LOCKED -> SETTLED / VOIDED)

    BettingEngine.sol
      - Sharded betting engine (16 shards, parallel writes)

    SettlementProcessor.sol
      - Batch settlement orchestrator

    UserVault.sol
      - User-based balance management

  oracle/
    PythAdapter.sol
      - Pyth Network oracle wrapper

    AuraVerifier.sol
      - AI attestation verification (ECDSA)

  account/
    SessionKeyManager.sol
      - Temporary session key authorization

    DelegatedSigner.sol
      - EIP-712 signature verification

  libraries/
    MicroEventLib.sol
      - Event ID generation and window validation

    BetLib.sol
      - Bet validation and payout calculation

    ShardLib.sol
      - Storage sharding logic

  interfaces/
    - 6 interface files

--------------------------------------------------------------------
DEPLOYED CONTRACTS (MONAD TESTNET)
--------------------------------------------------------------------

AuraVerifier        : 0x758658c989648597db25630264a7b2b58d849099
PythAdapter         : 0x85348658d774e024b4ae31e16e0da9a3e16703a1
UserVault           : 0x472d1f17e59a952f2856bd7c5dfa48fc017746bd
DelegatedSigner     : 0xeee18e9c6f8f6d5999053c22a2919bed74689c9f
EventManager        : 0x794fdb692cc382643a2da6d3036ba1b17beaec98
BettingEngine       : 0x3605249370edaca26da4f8f8d6eee9bb63a45ed9
SessionKeyManager   : 0x21da3d98da6e97ff10d0c493feb97c697832daa6
SettlementProcessor : 0x5cdeddbc014c919a16da9f6061f92fca8e1cc8ca

--------------------------------------------------------------------
PARALLEL EXECUTION DESIGN
--------------------------------------------------------------------

userBets[user][eventId]
  -> User-specific storage slot (PARALLEL)

poolShards[eventId][outcome][shard]
  -> 16 independent shards (93.75% parallel)

UserVault._balances[user]
  -> User-specific storage slot (PARALLEL)

Shard index derivation:

uint8(uint160(user) & 0x0F)

This creates 16 independent write slots based on user address.

--------------------------------------------------------------------
TESTING
--------------------------------------------------------------------

Run all tests:
forge test

Specific contract:
forge test --match-contract EventManager

Verbose output:
forge test -vvv

Gas snapshot:
forge snapshot

--------------------------------------------------------------------
PROJECT STRUCTURE
--------------------------------------------------------------------

MonoDash/
  src/            Solidity contracts
  test/
    unit/         Unit tests
    integration/  Integration test
    mocks/        Mock contracts
  script/
    Deploy.s.sol
    LocalDeploy.s.sol
  frontend/
    index.html
    monodashlogo.png
  foundry.toml
  start.sh

--------------------------------------------------------------------
USAGE FLOW
--------------------------------------------------------------------

1. Start frontend with start.sh
2. Connect MetaMask to Monad Testnet
3. Obtain test MON from faucet
4. Connect wallet via UI
5. Deposit MON
6. Create an event or place a bet
7. Wait for settlement
8. Claim winnings

--------------------------------------------------------------------
TECHNICAL DETAILS
--------------------------------------------------------------------

Solidity version : 0.8.24 (Cancun EVM)
Betting window   : 30–60 seconds
Outcomes         : 2–10
Minimum bet      : 0.001 MON
Maximum bet      : 100 MON
House fee        : 2% (200 bps)
Shard count      : 16
Parallel ratio   : 93.75%

--------------------------------------------------------------------
LICENSE
--------------------------------------------------------------------

MIT
