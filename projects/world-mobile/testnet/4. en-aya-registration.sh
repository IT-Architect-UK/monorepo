#!/usr/bin/env bash

echo "Registering the validator node on the AYA chain"

# Define Variables
aya_home="/opt/aya"

# Prompt user for configuration variables
echo "Prompting user for configuration variables..."

# Prompt for CHAIN ID with a default value
read -p "Enter CHAIN_ID (default: aya_preview_501): " CHAIN_ID
CHAIN_ID=${CHAIN_ID:-aya_preview_501}

# Prompt for MONIKER with a default value
read -p "Enter MONIKER (default: Skint-Earth-Node-1): " MONIKER
MONIKER=${MONIKER:-Skint-Earth-Node-1}

# Prompt for ACCOUNT with a default value
read -p "Enter ACCOUNT (default: Skint-Earth-Node-1): " ACCOUNT
ACCOUNT=${ACCOUNT:-Skint-Earth-Node-1}

echo "Configured CHAIN_ID: $CHAIN_ID"
echo "Configured MONIKER: $MONIKER"
echo "Configured ACCOUNT: $ACCOUNT"

ayad tx staking create-validator \
  --amount=1uswmt \
  --pubkey="$(ayad tendermint show-validator --home ${aya_home})" \
  --moniker="$MONIKER" \
  --chain-id="$CHAIN_ID" \
  --commission-rate="0.10" \
  --commission-max-rate="0.20" \
  --commission-max-change-rate="0.01" \
  --min-self-delegation="1" \
  --from="$ACCOUNT" \
  --home ${aya_home} \
  --output json \
  --yes
