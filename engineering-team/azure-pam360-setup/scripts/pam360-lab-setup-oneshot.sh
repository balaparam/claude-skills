#!/usr/bin/env bash
# ============================================================
#  PAM360 Lab — Single-shot setup script
#  Run in Azure Cloud Shell (https://shell.azure.com)
#  Usage: bash pam360-lab-setup.sh
# ============================================================
set -euo pipefail

# ─── CHANGE ONLY THESE TWO LINES ────────────────────────────
ADMIN_PASSWORD="ToCumu1u\$@123"          # Must: 12+ chars, upper+lower+digit+special
LOCATION="eastus"                        # Azure region
# ─────────────────────────────────────────────────────────────

RG="rg-pam360-lab"
VNET="vnet-pam360"
STORAGE="stpam360$(openssl rand -hex 4)"
PAM_VM="vm-pam360-server"
EP1_VM="vm-win-endpoint-01"
EP2_VM="vm-win-endpoint-02"
ADMIN_USER="pamadmin"
IMAGE="Win2022Datacenter"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   PAM360 Lab — Starting full deployment      ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── 1. Resource Group ────────────────────────────────────────
echo "▶ [1/9] Creating resource group..."
az group create --name "$RG" --location "$LOCATION" -o none
echo "  ✓ $RG"

# ── 2. Virtual Network ───────────────────────────────────────
echo "▶ [2/9] Creating VNet and subnets..."
az network vnet create --resource-group "$RG" --name "$VNET" \
  --address-prefix "10.10.0.0/16" --location "$LOCATION" -o none

az network vnet subnet create --resource-group "$RG" --vnet-name "$VNET" \
  --name "snet-pam-server" --address-prefix "10.10.1.0/24" -o none

az network vnet subnet create --resource-group "$RG" --vnet-name "$VNET" \
  --name "snet-endpoints" --address-prefix "10.10.2.0/24" -o none
echo "  ✓ VNet 10.10.0.0/16 | PAM subnet 10.10.1.0/24 | Endpoint subnet 10.10.2.0/24"

# ── 3. NSG — PAM360 server ───────────────────────────────────
echo "▶ [3/9] Creating NSGs..."
az network nsg create --resource-group "$RG" --name "nsg-pam-server" --location "$LOCATION" -o none

# Allow PAM360 web console from internet
az network nsg rule create --resource-group "$RG" --nsg-name "nsg-pam-server" \
  --name "Allow-PAM360-Console" --priority 100 --protocol Tcp \
  --destination-port-ranges 8282 --access Allow --direction Inbound \
  --source-address-prefixes "Internet" -o none

# Allow RDP to PAM server only from within VNet (initial setup)
az network nsg rule create --resource-group "$RG" --nsg-name "nsg-pam-server" \
  --name "Allow-RDP-VNet" --priority 200 --protocol Tcp \
  --destination-port-ranges 3389 --access Allow --direction Inbound \
  --source-address-prefixes "10.10.0.0/16" -o none

# NSG for endpoints — RDP only from PAM360 subnet, no internet
az network nsg create --resource-group "$RG" --name "nsg-endpoints" --location "$LOCATION" -o none

az network nsg rule create --resource-group "$RG" --nsg-name "nsg-endpoints" \
  --name "Allow-RDP-from-PAM-only" --priority 100 --protocol Tcp \
  --destination-port-ranges 3389 --access Allow --direction Inbound \
  --source-address-prefixes "10.10.1.0/24" -o none

az network nsg rule create --resource-group "$RG" --nsg-name "nsg-endpoints" \
  --name "Deny-Internet-RDP" --priority 200 --protocol Tcp \
  --destination-port-ranges 3389 --access Deny --direction Inbound \
  --source-address-prefixes "Internet" -o none

# Attach NSGs to subnets
az network vnet subnet update --resource-group "$RG" --vnet-name "$VNET" \
  --name "snet-pam-server" --network-security-group "nsg-pam-server" -o none

az network vnet subnet update --resource-group "$RG" --vnet-name "$VNET" \
  --name "snet-endpoints" --network-security-group "nsg-endpoints" -o none
echo "  ✓ NSGs created and attached"

# ── 4. Storage (boot diagnostics) ────────────────────────────
echo "▶ [4/9] Creating storage account..."
az storage account create --resource-group "$RG" --name "$STORAGE" \
  --sku Standard_LRS --location "$LOCATION" -o none
echo "  ✓ $STORAGE"

# ── 5. PAM360 Server VM ──────────────────────────────────────
echo "▶ [5/9] Creating PAM360 server VM (Standard_B4ms — ~5 min)..."
az network public-ip create --resource-group "$RG" --name "pip-pam360" \
  --allocation-method Static --sku Standard --location "$LOCATION" -o none

az network nic create --resource-group "$RG" --name "nic-pam360" \
  --vnet-name "$VNET" --subnet "snet-pam-server" \
  --public-ip-address "pip-pam360" --private-ip-address "10.10.1.10" \
  --location "$LOCATION" -o none

az vm create --resource-group "$RG" --name "$PAM_VM" \
  --nics "nic-pam360" --image "$IMAGE" --size "Standard_D4s_v3" \
  --admin-username "$ADMIN_USER" --admin-password "$ADMIN_PASSWORD" \
  --os-disk-size-gb 128 --storage-sku Premium_LRS \
  --boot-diagnostics-storage "$STORAGE" \
  --enable-agent true --location "$LOCATION" \
  --tags "role=pam360-server" -o none

az vm extension set --resource-group "$RG" --vm-name "$PAM_VM" \
  --name AADLoginForWindows \
  --publisher Microsoft.Azure.ActiveDirectory --version 2.0 -o none
echo "  ✓ $PAM_VM created (Standard_B4ms, 4 vCPU, 16 GB)"

# ── 6. Endpoint VM 1 ─────────────────────────────────────────
echo "▶ [6/9] Creating endpoint VM 1 (Standard_B2s — ~3 min)..."
az network nic create --resource-group "$RG" --name "nic-endpoint-01" \
  --vnet-name "$VNET" --subnet "snet-endpoints" \
  --private-ip-address "10.10.2.10" --location "$LOCATION" -o none

az vm create --resource-group "$RG" --name "$EP1_VM" \
  --nics "nic-endpoint-01" --image "$IMAGE" --size "Standard_D2s_v3" \
  --admin-username "$ADMIN_USER" --admin-password "$ADMIN_PASSWORD" \
  --os-disk-size-gb 64 --storage-sku StandardSSD_LRS \
  --boot-diagnostics-storage "$STORAGE" \
  --enable-agent true --location "$LOCATION" \
  --tags "role=pam360-endpoint" -o none

az vm extension set --resource-group "$RG" --vm-name "$EP1_VM" \
  --name AADLoginForWindows \
  --publisher Microsoft.Azure.ActiveDirectory --version 2.0 -o none
echo "  ✓ $EP1_VM created (Standard_B2s, 2 vCPU, 4 GB, no public IP)"

# ── 7. Endpoint VM 2 ─────────────────────────────────────────
echo "▶ [7/9] Creating endpoint VM 2 (Standard_B2s — ~3 min)..."
az network nic create --resource-group "$RG" --name "nic-endpoint-02" \
  --vnet-name "$VNET" --subnet "snet-endpoints" \
  --private-ip-address "10.10.2.11" --location "$LOCATION" -o none

az vm create --resource-group "$RG" --name "$EP2_VM" \
  --nics "nic-endpoint-02" --image "$IMAGE" --size "Standard_D2s_v3" \
  --admin-username "$ADMIN_USER" --admin-password "$ADMIN_PASSWORD" \
  --os-disk-size-gb 64 --storage-sku StandardSSD_LRS \
  --boot-diagnostics-storage "$STORAGE" \
  --enable-agent true --location "$LOCATION" \
  --tags "role=pam360-endpoint" -o none

az vm extension set --resource-group "$RG" --vm-name "$EP2_VM" \
  --name AADLoginForWindows \
  --publisher Microsoft.Azure.ActiveDirectory --version 2.0 -o none
echo "  ✓ $EP2_VM created (Standard_B2s, 2 vCPU, 4 GB, no public IP)"

# ── 8. Entra ID App Registration for PAM360 SSO ──────────────
echo "▶ [8/9] Creating Entra ID App Registration for PAM360 SSO..."
TENANT_ID=$(az account show --query tenantId -o tsv)
PAM_IP=$(az network public-ip show --resource-group "$RG" --name "pip-pam360" --query ipAddress -o tsv)

APP_ID=$(az ad app create \
  --display-name "ManageEngine PAM360 Lab" \
  --sign-in-audience "AzureADMyOrg" \
  --web-redirect-uris "https://${PAM_IP}:8282/samlResponse" \
  --query appId -o tsv)

az ad sp create --id "$APP_ID" -o none

CLIENT_SECRET=$(az ad app credential reset --id "$APP_ID" --years 1 --query password -o tsv)

# Assign VM login role on endpoints to current user
CURRENT_USER=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
if [[ -n "$CURRENT_USER" ]]; then
  SUB_ID=$(az account show --query id -o tsv)
  for VM in "$EP1_VM" "$EP2_VM"; do
    VM_ID=$(az vm show --resource-group "$RG" --name "$VM" --query id -o tsv)
    az role assignment create --role "Virtual Machine Administrator Login" \
      --assignee-object-id "$CURRENT_USER" --assignee-principal-type User \
      --scope "$VM_ID" -o none 2>/dev/null || true
  done
fi
echo "  ✓ App Registration created (App ID: $APP_ID)"

# ── 9. Done — Print Summary ───────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  DEPLOYMENT COMPLETE ✓                      ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  VIRTUAL MACHINES                                           ║"
printf "║  PAM360 Server  : %-42s║\n" "$PAM_VM  →  10.10.1.10"
printf "║  Public IP      : %-42s║\n" "$PAM_IP"
printf "║  Endpoint 01    : %-42s║\n" "$EP1_VM  →  10.10.2.10  (no pub IP)"
printf "║  Endpoint 02    : %-42s║\n" "$EP2_VM  →  10.10.2.11  (no pub IP)"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  LOCAL ADMIN CREDENTIALS (for VM login & PAM360 vault)     ║"
printf "║  Username : %-49s║\n" "$ADMIN_USER"
printf "║  Password : %-49s║\n" "$ADMIN_PASSWORD"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  ENTRA ID SSO — paste these into PAM360 SAML config        ║"
printf "║  Tenant ID      : %-42s║\n" "$TENANT_ID"
printf "║  App (Client) ID: %-42s║\n" "$APP_ID"
printf "║  Client Secret  : %-42s║\n" "$CLIENT_SECRET"
printf "║  SSO Login URL  : %-42s║\n" "https://login.microsoftonline.com/$TENANT_ID/saml2"
printf "║  IDP Entity ID  : %-42s║\n" "https://sts.windows.net/$TENANT_ID/"
printf "║  Reply URL (ACS): %-42s║\n" "https://$PAM_IP:8282/samlResponse"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  NEXT STEPS                                                 ║"
echo "║  1. RDP to PAM360: mstsc /v:$PAM_IP                        ║"
echo "║  2. Download & install PAM360 on that VM (port 8282)        ║"
echo "║  3. Open https://$PAM_IP:8282 and configure SAML SSO       ║"
echo "║  4. Add 10.10.2.10 and 10.10.2.11 as Windows targets       ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  STOP COSTS WHEN DONE                                       ║"
echo "║  az group delete --name rg-pam360-lab --yes --no-wait       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
