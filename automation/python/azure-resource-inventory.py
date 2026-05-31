#!/usr/bin/env python3
"""
Azure Resource Inventory
Queries all resources across an Azure subscription and outputs a formatted
CSV and console summary grouped by resource type and location.

Prerequisites:
    pip install azure-identity azure-mgmt-resource azure-mgmt-subscription

Authentication:
    Uses DefaultAzureCredential — supports az login, managed identity, and
    environment variables (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET).

Usage:
    python3 azure-resource-inventory.py
    python3 azure-resource-inventory.py --subscription <subscription-id>
    python3 azure-resource-inventory.py --output inventory.csv
"""

import argparse
import csv
import sys
from collections import defaultdict
from datetime import datetime, timezone

try:
    from azure.identity import DefaultAzureCredential
    from azure.mgmt.resource import ResourceManagementClient
    from azure.mgmt.subscription import SubscriptionClient
except ImportError:
    print("ERROR: Required packages not installed.")
    print("Run: pip install azure-identity azure-mgmt-resource azure-mgmt-subscription")
    sys.exit(1)


def get_subscriptions(credential):
    client = SubscriptionClient(credential)
    return [s for s in client.subscriptions.list()]


def get_resources(credential, subscription_id):
    client = ResourceManagementClient(credential, subscription_id)
    return list(client.resources.list())


def parse_resource_group(resource_id):
    parts = resource_id.split("/")
    try:
        idx = parts.index("resourceGroups")
        return parts[idx + 1]
    except (ValueError, IndexError):
        return "unknown"


def build_rows(subscription, resources):
    rows = []
    for r in resources:
        rows.append({
            "subscription_id": subscription.subscription_id,
            "subscription_name": subscription.display_name,
            "resource_group": parse_resource_group(r.id),
            "resource_name": r.name,
            "resource_type": r.type,
            "location": r.location or "global",
            "tags": str(r.tags or {}),
        })
    return rows


def print_summary(rows):
    by_type = defaultdict(int)
    by_location = defaultdict(int)
    for row in rows:
        by_type[row["resource_type"]] += 1
        by_location[row["location"]] += 1

    print(f"\n{'='*60}")
    print(f"  Total resources: {len(rows)}")
    print(f"{'='*60}")
    print("\nBy resource type:")
    for rtype, count in sorted(by_type.items(), key=lambda x: -x[1]):
        print(f"  {count:>4}  {rtype}")
    print("\nBy location:")
    for loc, count in sorted(by_location.items(), key=lambda x: -x[1]):
        print(f"  {count:>4}  {loc}")
    print()


def write_csv(rows, path):
    if not rows:
        print("No resources found — CSV not written.")
        return
    fieldnames = list(rows[0].keys())
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Inventory written to: {path}")


def main():
    parser = argparse.ArgumentParser(description="Azure Resource Inventory")
    parser.add_argument("--subscription", help="Target subscription ID (default: all accessible)")
    parser.add_argument(
        "--output",
        default=f"azure-inventory-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}.csv",
        help="Output CSV file path",
    )
    args = parser.parse_args()

    print("Authenticating with Azure...")
    credential = DefaultAzureCredential()

    if args.subscription:
        subscriptions = [type("Sub", (), {
            "subscription_id": args.subscription,
            "display_name": args.subscription
        })()]
    else:
        print("Fetching subscriptions...")
        subscriptions = get_subscriptions(credential)
        print(f"Found {len(subscriptions)} subscription(s).")

    all_rows = []
    for sub in subscriptions:
        print(f"Querying: {sub.display_name} ({sub.subscription_id})")
        resources = get_resources(credential, sub.subscription_id)
        rows = build_rows(sub, resources)
        all_rows.extend(rows)
        print(f"  Found {len(rows)} resources.")

    print_summary(all_rows)
    write_csv(all_rows, args.output)


if __name__ == "__main__":
    main()
