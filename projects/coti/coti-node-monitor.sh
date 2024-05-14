#!/bin/bash

# Log setup to write output to coti-node-monitor.log in the current directory
exec > "$(dirname "$0")/coti-node-monitor.log" 2>&1

network="testnet"                                # mainnet | testnet
node_url="coti-testnet.skint.network"            # e.g. your-node-url.com
sync_ref_node_url="${network}-financialserver.coti.io"
unsync_tolerance=10
RESTART_COMMAND="systemctl restart cnode.service"

function get_last_index() {
    echo "$(curl -s "https://${node_url}/transaction/lastIndex" | jq -r '.lastIndex')"
}

function restart_if_unsynced() {
    echo "Performing sync check: $(date '+%A %d %m %Y %X')"

    local node_last_index=$(get_last_index "$node_url")
    local sync_ref_node_last_index=$(get_last_index "$sync_ref_node_url")

    # Check if $node_last_index and $sync_ref_node_last_index are integers
    if ! echo "$node_last_index" | grep -qE '^[0-9]+$' || ! echo "$sync_ref_node_last_index" | grep -qE '^[0-9]+$'; then
        echo "  Error getting last_index. Try again later"
        return 1
    fi

    local index_diff=$((sync_ref_node_last_index - node_last_index))
    if [ $index_diff -le $unsync_tolerance ]; then
        echo "  Node is synced (difference=$index_diff)."
    else
        echo "  Node is unsynced (difference=$index_diff). Performing restart."
        $RESTART_COMMAND
    fi
}

echo "Performing status check: $(date '+%A %d %m %Y %X')"
status_code=$(curl -o /dev/null -s -w '%{http_code}' "https://${network}-nodemanager.coti.io/nodes")

if [ "$status_code" -eq 200 ]; then
    if curl -s "https://${network}-nodemanager.coti.io/nodes" | grep -q "${node_url}"; then
        echo "  Node ${node_url} is connected."
        restart_if_unsynced
    else
        echo "  Node not found. Performing restart."
        $RESTART_COMMAND
    fi
else
    echo "  Node manager returned unusual status code: $status_code"
fi
