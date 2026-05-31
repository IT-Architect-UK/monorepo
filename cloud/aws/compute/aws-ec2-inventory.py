#!/usr/bin/env python3
"""
AWS EC2 Instance Inventory
Queries all EC2 instances across one or more regions and outputs a formatted
table and CSV report including instance metadata, state, and attached tags.

Prerequisites:
    pip install boto3 tabulate

Authentication:
    Uses the standard boto3 credential chain:
    AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY environment variables,
    ~/.aws/credentials, or EC2 instance profile.

Usage:
    python3 aws-ec2-inventory.py
    python3 aws-ec2-inventory.py --regions eu-west-2 us-east-1
    python3 aws-ec2-inventory.py --regions all --output inventory.csv
    python3 aws-ec2-inventory.py --state running
"""

import argparse
import csv
import sys
from datetime import datetime, timezone

try:
    import boto3
    from botocore.exceptions import BotoCoreError, ClientError
except ImportError:
    print("ERROR: boto3 not installed. Run: pip install boto3")
    sys.exit(1)

try:
    from tabulate import tabulate
    TABULATE_AVAILABLE = True
except ImportError:
    TABULATE_AVAILABLE = False


ALL_REGIONS = [
    "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1", "eu-north-1",
    "us-east-1", "us-east-2", "us-west-1", "us-west-2",
    "ap-southeast-1", "ap-southeast-2", "ap-northeast-1", "ap-south-1",
    "ca-central-1", "sa-east-1",
]


def get_tag(tags, key):
    if not tags:
        return ""
    for tag in tags:
        if tag.get("Key") == key:
            return tag.get("Value", "")
    return ""


def get_instances(region, state_filter=None):
    try:
        ec2 = boto3.client("ec2", region_name=region)
        filters = []
        if state_filter:
            filters.append({"Name": "instance-state-name", "Values": [state_filter]})

        paginator = ec2.get_paginator("describe_instances")
        instances = []
        for page in paginator.paginate(Filters=filters):
            for reservation in page["Reservations"]:
                for inst in reservation["Instances"]:
                    instances.append(inst)
        return instances
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code in ("AuthFailure", "UnauthorizedOperation", "InvalidClientTokenId"):
            print(f"  [{region}] Access denied — skipping.")
        else:
            print(f"  [{region}] Error: {e}")
        return []
    except BotoCoreError as e:
        print(f"  [{region}] Connection error: {e}")
        return []


def build_row(instance, region):
    launch_time = instance.get("LaunchTime")
    launch_str = launch_time.strftime("%Y-%m-%d %H:%M") if launch_time else ""

    return {
        "region": region,
        "instance_id": instance.get("InstanceId", ""),
        "name": get_tag(instance.get("Tags"), "Name"),
        "environment": get_tag(instance.get("Tags"), "Environment"),
        "instance_type": instance.get("InstanceType", ""),
        "state": instance.get("State", {}).get("Name", ""),
        "private_ip": instance.get("PrivateIpAddress", ""),
        "public_ip": instance.get("PublicIpAddress", ""),
        "ami_id": instance.get("ImageId", ""),
        "key_name": instance.get("KeyName", ""),
        "vpc_id": instance.get("VpcId", ""),
        "subnet_id": instance.get("SubnetId", ""),
        "launch_time": launch_str,
        "platform": instance.get("Platform", "linux"),
    }


def print_table(rows):
    if not rows:
        print("No instances found.")
        return

    headers = [
        "Region", "Instance ID", "Name", "Type", "State",
        "Private IP", "Public IP", "VPC", "Launch Time",
    ]
    table_rows = [
        [
            r["region"], r["instance_id"], r["name"] or "(unnamed)",
            r["instance_type"], r["state"],
            r["private_ip"], r["public_ip"] or "",
            r["vpc_id"], r["launch_time"],
        ]
        for r in rows
    ]

    if TABULATE_AVAILABLE:
        print(tabulate(table_rows, headers=headers, tablefmt="github"))
    else:
        print("\t".join(headers))
        for row in table_rows:
            print("\t".join(str(c) for c in row))


def write_csv(rows, path):
    if not rows:
        return
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"\nCSV written to: {path}")


def print_summary(rows):
    from collections import Counter
    state_counts = Counter(r["state"] for r in rows)
    type_counts  = Counter(r["instance_type"] for r in rows)
    region_counts = Counter(r["region"] for r in rows)

    print(f"\n{'='*55}")
    print(f"  Total instances: {len(rows)}")
    print(f"{'='*55}")
    print("By state:")
    for state, count in sorted(state_counts.items(), key=lambda x: -x[1]):
        print(f"  {count:>4}  {state}")
    print("By type:")
    for itype, count in sorted(type_counts.items(), key=lambda x: -x[1]):
        print(f"  {count:>4}  {itype}")
    print("By region:")
    for region, count in sorted(region_counts.items(), key=lambda x: -x[1]):
        print(f"  {count:>4}  {region}")
    print()


def main():
    parser = argparse.ArgumentParser(description="AWS EC2 Instance Inventory")
    parser.add_argument(
        "--regions", nargs="+", default=["eu-west-2"],
        help="Regions to query, or 'all' for all common regions (default: eu-west-2)"
    )
    parser.add_argument("--state",  help="Filter by state: running, stopped, terminated")
    parser.add_argument(
        "--output",
        default=f"ec2-inventory-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}.csv",
        help="Output CSV path"
    )
    parser.add_argument("--no-csv", action="store_true", help="Skip CSV output")
    args = parser.parse_args()

    regions = ALL_REGIONS if args.regions == ["all"] else args.regions

    print(f"EC2 Inventory — {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
    print(f"Querying {len(regions)} region(s)...\n")

    all_rows = []
    for region in regions:
        print(f"Scanning {region}...")
        instances = get_instances(region, state_filter=args.state)
        rows = [build_row(inst, region) for inst in instances]
        all_rows.extend(rows)
        print(f"  Found {len(rows)} instance(s).")

    print()
    print_table(all_rows)
    print_summary(all_rows)

    if not args.no_csv:
        write_csv(all_rows, args.output)


if __name__ == "__main__":
    main()
