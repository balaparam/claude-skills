#!/usr/bin/env bash
# Tear down the entire PAM360 lab to stop Azure costs
# DESTRUCTIVE — deletes all resources in the resource group
# Usage: bash 07-teardown.sh [--resource-group <name>] [--yes]

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-pam360-lab}"
APP_DISPLAY_NAME="ManageEngine PAM360 Lab"
AUTO_CONFIRM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --yes)            AUTO_CONFIRM=true;   shift   ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo "=========================================="
echo " PAM360 Lab Teardown"
echo " Resource Group: $RESOURCE_GROUP"
echo " This will DELETE all resources permanently."
echo "=========================================="

if [[ "$AUTO_CONFIRM" != "true" ]]; then
  read -rp "Type 'delete' to confirm: " CONFIRM
  [[ "$CONFIRM" != "delete" ]] && { echo "Cancelled."; exit 0; }
fi

# Delete App Registration
echo "[1/2] Removing Entra ID App Registration..."
APP_ID=$(az ad app list --display-name "$APP_DISPLAY_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)
if [[ -n "$APP_ID" ]]; then
  az ad app delete --id "$APP_ID" && echo "  App Registration deleted."
else
  echo "  No app registration found — skipping."
fi

# Delete entire resource group (VMs, VNet, NSGs, storage, IPs)
echo "[2/2] Deleting resource group $RESOURCE_GROUP (all resources)..."
az group delete \
  --name "$RESOURCE_GROUP" \
  --yes \
  --no-wait

echo ""
echo "Resource group deletion queued. Azure will clean up all resources in ~5 minutes."
echo "Monitor: az group show --name $RESOURCE_GROUP --query provisioningState"
