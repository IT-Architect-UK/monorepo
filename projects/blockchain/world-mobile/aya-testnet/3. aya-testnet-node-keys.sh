#!/bin/bash

# Log file location
LOG_DIR="/logs"
LOG_FILE="${LOG_DIR}/aya-testnet-node-keys.log"

# Ensure log directory exists
if [ ! -d "$LOG_DIR" ]; then
    sudo mkdir -p "$LOG_DIR"
    echo "Created log directory: ${LOG_DIR}"
fi

# Function to write log with timestamp
write_log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | sudo tee -a "$LOG_FILE"
}

# Generating AYA Node Keys
write_log "Generating AYA Node Keys"
# Creating temp File to store keys
output_file="/home/${USER}/aya-node/node-keys.tmp"
mkdir -p "$(dirname "$output_file")"
cd $HOME/aya-node
# Generating keys
./target/release/aya-node key generate > "$output_file"
echo "Keys have been saved to $output_file"
write_log "Keys have been saved to $output_file"
more $output_file

# Inspecting Keys Using the Secret Phrase
write_log "Inspecting Keys Using the Secret Phrase"
secret_phrase=$(grep "Secret phrase:" "$output_file" | awk -F: '{print $2}' | sed 's/^ *//;s/ *$//')
echo "Secret Phrase: $secret_phrase"
if [ -z "$secret_phrase" ]; then
  echo "Secret phrase not found in $output_file"
  exit 1
fi
echo "The secret phrase has been extracted: $secret_phrase"
./target/release/aya-node key inspect "$secret_phrase"

# Setting Values for AURA_KEY, GRANDPA_KEY and IM_ONLINE_KEY
write_log "Setting Values for AURA_KEY, GRANDPA_KEY and IM_ONLINE_KEY"
secret_seed=$(grep "Secret seed:" "$output_file" | awk -F: '{print $2}' | sed 's/^ *//;s/ *$//')
echo "Secret Phrase: $secret_seed"
if [ -z "$secret_seed" ]; then
  echo "Secret phrase not found in $output_file"
  exit 1
fi
echo "The secret phrase has been extracted: $secret_seed"
# Export the secret seed to a variable
export SECRET_SEED="$secret_seed"
# Set the AURA_KEY, GRANDPA_KEY and IM_ONLINE_KEY values
./target/release/aya-node key insert \
    --base-path data/validator \
    --chain wm-devnet-chainspec.json \
    --key-type aura \
    --scheme sr25519 \
    --suri "${SECRET_SEED}";

./target/release/aya-node key insert \
    --base-path data/validator \
    --chain wm-devnet-chainspec.json \
    --key-type gran \
    --scheme ed25519 \
    --suri "${SECRET_SEED}";

./target/release/aya-node key insert \
    --base-path data/validator \
    --chain wm-devnet-chainspec.json \
    --key-type imon \
    --scheme sr25519 \
    --suri "${SECRET_SEED}";
# Checking if the keys were set correctly
ls -l data/validator/chains/aya_devnet/keystore/;

# Triggering Key Rotation
write_log "Triggering Key Rotation"
# Run the curl command and store the output in a variable
output=$(curl -H "Content-Type: application/json" -d '{"id":1, "jsonrpc":"2.0", "method": "author_rotateKeys"}' http://localhost:9944/)
# Write the output to a temp file
echo "$output" > ~/aya-node/rotated-keys-string.tmp
# Extract the result from the output and store it in a variable
rotated_keys_string=$(echo "$output" | jq -r '.result')
# Split the rotated keys string into AURA, GRANDPA, and IMONLINE keys
AURA_KEY=${rotated_keys_string:0:66}
GRANDPA_KEY="0x${rotated_keys_string:66:64}"
IMONLINE_KEY="0x${rotated_keys_string:130:64}"
# Format the output
formatted_output="AURA_KEY: $AURA_KEY\nGRANDPA_KEY: $GRANDPA_KEY\nIMONLINE_KEY: $IMONLINE_KEY"
# Write the formatted output to a temp file and overwrite any existing file
echo -e "$formatted_output" > ~/aya-node/rotated-keys.tmp
# Print the result to verify
echo -e "Formatted Output:\n$formatted_output"
