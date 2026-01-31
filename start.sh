#!/bin/bash
# MonoDash - Monad Testnet
# Run: chmod +x start.sh && ./start.sh

set -e

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║       MonoDash - Monad Testnet       ║"
echo "  ╚══════════════════════════════════════╝"
echo ""

# 1. Load environment
if [ -f .env ]; then
    source .env
    echo "[1/2] Environment loaded."
else
    echo "[!] .env file not found. Copy .env and fill in DEPLOYER_PRIVATE_KEY."
    exit 1
fi

# 2. Serve frontend
echo "[2/2] Starting frontend..."
echo ""
echo "  Open: http://localhost:8080"
echo ""
echo "  MetaMask Setup:"
echo "    1. Add Monad Testnet to MetaMask:"
echo "       - Network Name: Monad Testnet"
echo "       - RPC URL: https://testnet-rpc.monad.xyz"
echo "       - Chain ID: 10143"
echo "       - Currency: MON"
echo "       - Explorer: https://testnet.monadscan.com"
echo "    2. Get testnet MON from faucet"
echo "    3. Connect wallet in the UI"
echo "    4. Deposit MON, create events, and dash!"
echo ""
echo "  Deploy contracts (if not already deployed):"
echo "    source .env && forge script script/Deploy.s.sol --rpc-url \$MONAD_RPC_URL --broadcast --legacy"
echo ""
echo "  Press Ctrl+C to stop"
echo ""

cd frontend
python3 -m http.server 8080
