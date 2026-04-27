#!/usr/bin/env bash
# Azure infrastructure setup for ManageEngine PAM360 testing environment
# Prerequisites: Azure CLI installed and logged in (az login)
# Usage: bash 01-create-infrastructure.sh [--resource-group <name>] [--location <region>]

set -euo pipefail

# ─────────────────────────────────────────────
# CONFIGURATION — edit these variables as needed
# ─────────────────────────────────────────────
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-pam360-lab}"
LOCATION="${LOCATION:-eastus}"
VNET_NAME="vnet-pam360"
SUBNET_PAM="snet-pam-server"
SUBNET_ENDPOINTS="snet-endpoints"
NSG_PAM="nsg-pam-server"
NSG_ENDPOINTS="nsg-endpoints"
STORAGE_ACCOUNT="stpam360diag$(openssl rand -hex 4)"
ADMIN_USERNAME="${ADMIN_USERNAME:-pamadmin}"
# Password must meet Azure complexity (12+ chars, upper/lower/digit/special)
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

# ─────────────────────────────────────────────
# ARGUMENT PARSING
# ─────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --location)       LOCATION="$2";       shift 2 ;;
    --admin-username) ADMIN_USERNAME="$2"; shift 2 ;;
    --admin-password) ADMIN_PASSWORD="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$ADMIN_PASSWORD" ]]; then
  echo "ERROR: Set ADMIN_PASSWORD env var or pass --admin-password"
  echo "       Must be 12+ chars with upper, lower, digit, and special character."
  exit 1
fi

echo "=========================================="
echo " PAM360 Lab Infrastructure Setup"
echo " Resource Group : $RESOURCE_GROUP"
echo " Location       : $LOCATION"
echo "=========================================="

# ─────────────────────────────────────────────
# 1. RESOURCE GROUP
# ─────────────────────────────────────────────
echo "[1/8] Creating resource group..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --tags "project=pam360-lab" "environment=test" \
  --output table

# ─────────────────────────────────────────────
# 2. VIRTUAL NETWORK & SUBNETS
# ─────────────────────────────────────────────
echo "[2/8] Creating VNet and subnets..."
az network vnet create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VNET_NAME" \
  --address-prefix "10.10.0.0/16" \
  --location "$LOCATION" \
  --output table

# PAM360 server subnet
az network vnet subnet create \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$SUBNET_PAM" \
  --address-prefix "10.10.1.0/24" \
  --output table

# Windows endpoint VMs subnet
az network vnet subnet create \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$SUBNET_ENDPOINTS" \
  --address-prefix "10.10.2.0/24" \
  --output table

# ─────────────────────────────────────────────
# 3. NETWORK SECURITY GROUPS
# ─────────────────────────────────────────────
echo "[3/8] Creating NSGs..."

# NSG for PAM360 server
az network nsg create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$NSG_PAM" \
  --location "$LOCATION" \
  --output table

# Allow HTTPS inbound for PAM360 web console (port 8282 default)
az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_PAM" \
  --name "Allow-PAM360-HTTPS" \
  --priority 100 \
  --protocol Tcp \
  --destination-port-ranges 8282 \
  --access Allow \
  --direction Inbound \
  --source-address-prefixes "Internet" \
  --output table

# Allow RDP only from endpoints subnet (admin access within VNet)
az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_PAM" \
  --name "Allow-RDP-VNet" \
  --priority 200 \
  --protocol Tcp \
  --destination-port-ranges 3389 \
  --access Allow \
  --direction Inbound \
  --source-address-prefixes "10.10.0.0/16" \
  --output table

# Deny all other inbound
az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_PAM" \
  --name "Deny-All-Inbound" \
  --priority 4000 \
  --protocol "*" \
  --destination-port-ranges "*" \
  --access Deny \
  --direction Inbound \
  --source-address-prefixes "*" \
  --output table

# NSG for Windows endpoints — no direct internet RDP; access via PAM360 only
az network nsg create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$NSG_ENDPOINTS" \
  --location "$LOCATION" \
  --output table

# Allow RDP only from PAM360 subnet (PAM360 proxies the session)
az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_ENDPOINTS" \
  --name "Allow-RDP-from-PAM-Subnet" \
  --priority 100 \
  --protocol Tcp \
  --destination-port-ranges 3389 \
  --access Allow \
  --direction Inbound \
  --source-address-prefixes "10.10.1.0/24" \
  --output table

# Deny direct internet RDP
az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name "$NSG_ENDPOINTS" \
  --name "Deny-Internet-RDP" \
  --priority 200 \
  --protocol Tcp \
  --destination-port-ranges 3389 \
  --access Deny \
  --direction Inbound \
  --source-address-prefixes "Internet" \
  --output table

# Associate NSGs to subnets
az network vnet subnet update \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$SUBNET_PAM" \
  --network-security-group "$NSG_PAM" \
  --output table

az network vnet subnet update \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$SUBNET_ENDPOINTS" \
  --network-security-group "$NSG_ENDPOINTS" \
  --output table

# ─────────────────────────────────────────────
# 4. STORAGE ACCOUNT (boot diagnostics)
# ─────────────────────────────────────────────
echo "[4/8] Creating storage account for diagnostics..."
az storage account create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$STORAGE_ACCOUNT" \
  --sku Standard_LRS \
  --location "$LOCATION" \
  --output table

echo ""
echo "✓ Infrastructure base layer complete."
echo "  VNet       : $VNET_NAME (10.10.0.0/16)"
echo "  PAM Subnet : $SUBNET_PAM (10.10.1.0/24)"
echo "  EP Subnet  : $SUBNET_ENDPOINTS (10.10.2.0/24)"
echo "  Storage    : $STORAGE_ACCOUNT"
echo ""
echo "Next: Run 02-create-pam360-vm.sh"

# Export for child scripts
export RESOURCE_GROUP LOCATION VNET_NAME SUBNET_PAM SUBNET_ENDPOINTS \
       STORAGE_ACCOUNT ADMIN_USERNAME ADMIN_PASSWORD
