#!/usr/bin/env bash
# Creates the ManageEngine PAM360 server VM (Windows Server 2022)
# Run AFTER 01-create-infrastructure.sh or export its variables first.
# Usage: bash 02-create-pam360-vm.sh

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-pam360-lab}"
LOCATION="${LOCATION:-eastus}"
VNET_NAME="${VNET_NAME:-vnet-pam360}"
SUBNET_PAM="${SUBNET_PAM:-snet-pam-server}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"
ADMIN_USERNAME="${ADMIN_USERNAME:-pamadmin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

PAM_VM_NAME="vm-pam360-server"
PAM_VM_SIZE="Standard_B4ms"         # 4 vCPU, 16 GB burstable — cheapest that meets PAM360 minimum
PAM_VM_IMAGE="Win2022Datacenter"
PAM_NIC="nic-pam360-server"
PAM_PUBLIC_IP="pip-pam360-server"
PAM_OS_DISK="osdisk-pam360"

if [[ -z "$ADMIN_PASSWORD" ]]; then
  echo "ERROR: ADMIN_PASSWORD not set."
  exit 1
fi

echo "=========================================="
echo " Creating PAM360 Server VM: $PAM_VM_NAME"
echo "=========================================="

# ─────────────────────────────────────────────
# 1. PUBLIC IP for PAM360 web console access
# ─────────────────────────────────────────────
echo "[1/4] Creating public IP..."
az network public-ip create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PAM_PUBLIC_IP" \
  --allocation-method Static \
  --sku Standard \
  --location "$LOCATION" \
  --dns-name "pam360-$(openssl rand -hex 4)" \
  --output table

# ─────────────────────────────────────────────
# 2. NIC
# ─────────────────────────────────────────────
echo "[2/4] Creating NIC..."
az network nic create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PAM_NIC" \
  --vnet-name "$VNET_NAME" \
  --subnet "$SUBNET_PAM" \
  --public-ip-address "$PAM_PUBLIC_IP" \
  --private-ip-address "10.10.1.10" \
  --location "$LOCATION" \
  --output table

# ─────────────────────────────────────────────
# 3. WINDOWS VM
# ─────────────────────────────────────────────
echo "[3/4] Creating Windows Server VM for PAM360 (this takes ~5 minutes)..."
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PAM_VM_NAME" \
  --nics "$PAM_NIC" \
  --image "$PAM_VM_IMAGE" \
  --size "$PAM_VM_SIZE" \
  --admin-username "$ADMIN_USERNAME" \
  --admin-password "$ADMIN_PASSWORD" \
  --os-disk-name "$PAM_OS_DISK" \
  --os-disk-size-gb 128 \
  --storage-sku Premium_LRS \
  --boot-diagnostics-storage "$STORAGE_ACCOUNT" \
  --enable-agent true \
  --patch-mode AutomaticByPlatform \
  --enable-auto-update true \
  --location "$LOCATION" \
  --tags "role=pam360-server" "project=pam360-lab" \
  --output table

# ─────────────────────────────────────────────
# 4. ENABLE AZURE AD / ENTRA ID LOGIN (no AD DS required)
# ─────────────────────────────────────────────
echo "[4/4] Installing AADLoginForWindows extension (Entra ID login)..."
az vm extension set \
  --resource-group "$RESOURCE_GROUP" \
  --vm-name "$PAM_VM_NAME" \
  --name AADLoginForWindows \
  --publisher Microsoft.Azure.ActiveDirectory \
  --version 2.0 \
  --output table

# Retrieve public IP for user
PAM_IP=$(az network public-ip show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PAM_PUBLIC_IP" \
  --query "ipAddress" -o tsv)

PAM_FQDN=$(az network public-ip show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PAM_PUBLIC_IP" \
  --query "dnsSettings.fqdn" -o tsv)

echo ""
echo "✓ PAM360 Server VM created."
echo "  VM Name     : $PAM_VM_NAME"
echo "  VM Size     : $PAM_VM_SIZE"
echo "  Private IP  : 10.10.1.10"
echo "  Public IP   : $PAM_IP"
echo "  FQDN        : $PAM_FQDN"
echo "  RDP (initial setup only): mstsc /v:$PAM_IP"
echo "  PAM360 console (after install): https://$PAM_FQDN:8282"
echo ""
echo "Next steps:"
echo "  1. RDP into $PAM_IP as $ADMIN_USERNAME"
echo "  2. Download PAM360 installer: https://www.manageengine.com/privileged-access-management/download.html"
echo "  3. Install PAM360 with default port 8282"
echo "  4. Run 03-create-endpoint-vms.sh"
