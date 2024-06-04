#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Ensure jq is installed
if ! command_exists jq; then
    echo "jq is not installed. Installing jq..."
    sudo apt update
    sudo apt install -y jq
else
    echo "jq is already installed."
fi

# Ensure xxd is installed
if ! command_exists xxd; then
    echo "xxd is not installed. Installing xxd..."
    sudo apt update
    sudo apt install -y xxd
else
    echo "xxd is already installed."
fi

# Ensure base64 is installed
if ! command_exists base64; then
    echo "base64 is not installed. Installing base64..."
    sudo apt update
    sudo apt install -y coreutils
else
    echo "base64 is already installed."
fi

# Ensure subwasm is installed
if ! command_exists subwasm; then
    echo "subwasm is not installed. Installing subwasm..."
    wget https://github.com/chevdor/subwasm/releases/download/v0.21.3/subwasm_linux_amd64_v0.21.3.deb
    sudo dpkg -i subwasm_linux_amd64_v0.21.3.deb
    rm subwasm_linux_amd64_v0.21.3.deb
else
    echo "subwasm is already installed."
fi

NODE_URL="http://localhost:9944"

# Function to get local node ID
get_local_node_id() {
  curl -s -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"system_localPeerId","params":[]}' $NODE_URL | jq -r '.result'
}

# Function to get the latest block number
get_latest_block_number() {
  curl -s -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","id":1,"method":"chain_getHeader","params":[]}' $NODE_URL | jq -r '.result.number' | xargs printf "%d\n"
}

# Function to get block hash from block number
get_block_hash() {
  local block_number=$1
  curl -s -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"chain_getBlockHash\",\"params\":[$block_number]}" $NODE_URL | jq -r '.result'
}

# Function to get block digest logs from block hash
get_block_digest_logs() {
  local block_hash=$1
  curl -s -H "Content-Type: application/json" -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"chain_getBlock\",\"params\":[\"$block_hash\"]}" $NODE_URL | jq -r '.result.block.header.digest.logs'
}

# Function to decode node ID from logs
decode_node_id() {
  local hex_string=$1
  echo "$hex_string" | xxd -r -p | base64 | subwasm -d | grep "PeerId" | awk '{print $2}'
}

local_node_id=$(get_local_node_id)
echo "Your Node ID: $local_node_id"

latest_block_number=$(get_latest_block_number)
echo "Latest Block Number: $latest_block_number"

while true; do
  new_block_number=$(get_latest_block_number)
  if [[ $new_block_number -gt $latest_block_number ]]; then
    for (( i = latest_block_number + 1; i <= new_block_number; i++ )); do
      block_hash=$(get_block_hash $i)
      echo "New Block Produced by Block number: $i, Block hash: $block_hash"
      logs=$(get_block_digest_logs $block_hash)
      echo "Processing log: Response: $logs"
      if [[ $logs != "null" ]]; then
        for log in $(echo $logs | jq -r '.[]'); do
          if [[ $log == 0x0561757261* ]]; then
            hex_part=${log:14}
            node_id=$(decode_node_id $hex_part)
            echo "Hex part: $hex_part"
            echo "Node ID: $node_id"
            if [[ $node_id == $local_node_id ]]; then
              echo "New Block Produced by: Your Node ($node_id): $i"
            else
              echo "New Block Produced by: $node_id: $i"
            fi
          fi
        done
      else
        echo "No logs found in the block details."
      fi
    done
    latest_block_number=$new_block_number
  fi
  sleep 5
done
