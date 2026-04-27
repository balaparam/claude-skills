#!/usr/bin/env bash
# Creates Windows endpoint VMs that will be managed by PAM360 JIT access
# These VMs have NO direct internet RDP — access only through PAM360
# Usage: bash 03-create-endpoint-vms.sh [--count <number>]

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-pam360-lab}"
LOCATION="${LOCATION:-eastus}"
VNET_NAME="${VNET_NAME:-vnet-pam360}"
SUBNET_ENDPOINTS="${SUBNET_ENDPOINTS:-snet-endpoints}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"
ADMIN_USERNAME="${ADMIN_USERNAME:-pamadmin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
ENDPOINT_COUNT="${ENDPOINT_COUNT:-2}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --count) ENDPOINT_COUNT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$ADMIN_PASSWORD" ]]; then
  echo "ERROR: ADMIN_PASSWORD not set."
  exit 1
fi

ENDPOINT_VM_SIZE="Standard_B2s"    # 2 vCPU, 4 GB burstable — cheapest viable Windows endpoint for POC
ENDPOINT_VM_IMAGE="Win2022Datacenter"

echo "=========================================="
echo " Creating $ENDPOINT_COUNT Windows Endpoint VM(s)"
echo " Access: PAM360 proxy ONLY (no direct RDP)"
echo "=========================================="

for i in $(seq 1 "$ENDPOINT_COUNT"); do
  VM_NAME="vm-win-endpoint-$(printf '%02d' "$i")"
  NIC_NAME="nic-endpoint-$(printf '%02d' "$i")"
  PRIVATE_IP="10.10.2.$(( 9 + i ))"   # .10, .11, .12, ...

  echo ""
  echo "--- Creating endpoint VM $i of $ENDPOINT_COUNT: $VM_NAME ($PRIVATE_IP) ---"

  # NIC with static private IP, NO public IP intentionally
  az network nic create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NIC_NAME" \
    --vnet-name "$VNET_NAME" \
    --subnet "$SUBNET_ENDPOINTS" \
    --private-ip-address "$PRIVATE_IP" \
    --location "$LOCATION" \
    --output table

  az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --nics "$NIC_NAME" \
    --image "$ENDPOINT_VM_IMAGE" \
    --size "$ENDPOINT_VM_SIZE" \
    --admin-username "$ADMIN_USERNAME" \
    --admin-password "$ADMIN_PASSWORD" \
    --os-disk-size-gb 64 \
    --storage-sku StandardSSD_LRS \
    --boot-diagnostics-storage "$STORAGE_ACCOUNT" \
    --enable-agent true \
    --patch-mode AutomaticByPlatform \
    --location "$LOCATION" \
    --tags "role=pam360-endpoint" "project=pam360-lab" "endpoint-id=$i" \
    --output table

  # Enable Entra ID login on endpoint (Entra ID auth, no AD DS)
  echo "  Installing AADLoginForWindows on $VM_NAME..."
  az vm extension set \
    --resource-group "$RESOURCE_GROUP" \
    --vm-name "$VM_NAME" \
    --name AADLoginForWindows \
    --publisher Microsoft.Azure.ActiveDirectory \
    --version 2.0 \
    --output table

  echo "  ✓ $VM_NAME created at $PRIVATE_IP"
done

echo ""
echo "=========================================="
echo " All endpoint VMs created."
echo " Summary of private IPs:"
for i in $(seq 1 "$ENDPOINT_COUNT"); do
  PRIVATE_IP="10.10.2.$(( 9 + i ))"
  echo "   vm-win-endpoint-$(printf '%02d' "$i") : $PRIVATE_IP"
done
echo ""
echo " These VMs have NO public IP."
echo " RDP access is ONLY via PAM360 at 10.10.1.10"
echo "=========================================="
echo ""
echo "Next: Run 04-configure-entra-id.sh to set up Entra ID app registration"
