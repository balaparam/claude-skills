#!/usr/bin/env bash
# Configure Entra ID (Azure AD) for PAM360 SSO and Entra ID-only authentication
# No Active Directory Domain Services (ADDS) required — cloud-native identity only
# Usage: bash 04-configure-entra-id.sh

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-pam360-lab}"
PAM_VM_NAME="${PAM_VM_NAME:-vm-pam360-server}"
APP_DISPLAY_NAME="ManageEngine PAM360 Lab"
REPLY_URL_PORT="8282"   # Default PAM360 HTTPS port

echo "=========================================="
echo " Entra ID Configuration for PAM360"
echo " Authentication: Entra ID only (no AD DS)"
echo "=========================================="

# ─────────────────────────────────────────────
# 1. APP REGISTRATION (OAuth 2.0 / SAML SSO)
# ─────────────────────────────────────────────
echo "[1/6] Creating Entra ID App Registration for PAM360..."

# Get PAM360 VM public IP / FQDN for reply URL
PAM_FQDN=$(az network public-ip list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?tags.role=='pam360-server' || contains(name,'pam360')].dnsSettings.fqdn | [0]" -o tsv 2>/dev/null || true)

PAM_PUBLIC_IP=$(az network public-ip list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?contains(name,'pam360')].ipAddress | [0]" -o tsv)

REPLY_URL="https://${PAM_FQDN:-$PAM_PUBLIC_IP}:${REPLY_URL_PORT}/samlResponse"
LOGOUT_URL="https://${PAM_FQDN:-$PAM_PUBLIC_IP}:${REPLY_URL_PORT}/samlLogout"

APP_ID=$(az ad app create \
  --display-name "$APP_DISPLAY_NAME" \
  --sign-in-audience "AzureADMyOrg" \
  --web-redirect-uris "$REPLY_URL" \
  --query "appId" -o tsv)

echo "  App Registration created. App ID: $APP_ID"

# Create service principal
SP_ID=$(az ad sp create --id "$APP_ID" --query "id" -o tsv)
echo "  Service Principal ID: $SP_ID"

# ─────────────────────────────────────────────
# 2. CLIENT SECRET (for OAuth client credentials)
# ─────────────────────────────────────────────
echo "[2/6] Creating client secret..."
CLIENT_SECRET=$(az ad app credential reset \
  --id "$APP_ID" \
  --years 1 \
  --query "password" -o tsv)

echo "  Client Secret created (store securely — shown only once)."

# ─────────────────────────────────────────────
# 3. ENTRA ID ROLES FOR VM LOGIN
#    Assign roles to allow Entra ID users to log
#    into the VMs directly without AD DS
# ─────────────────────────────────────────────
echo "[3/6] Assigning Entra ID VM login roles..."

SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
TENANT_ID=$(az account show --query "tenantId" -o tsv)

# Get VM resource IDs
PAM_VM_RESOURCE_ID=$(az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$PAM_VM_NAME" \
  --query "id" -o tsv)

# Virtual Machine Administrator Login — allows Entra ID users to RDP as local admin
# Assign to the current signed-in user as baseline
CURRENT_USER_OID=$(az ad signed-in-user show --query "id" -o tsv)

az role assignment create \
  --role "Virtual Machine Administrator Login" \
  --assignee-object-id "$CURRENT_USER_OID" \
  --assignee-principal-type User \
  --scope "$PAM_VM_RESOURCE_ID" \
  --output table

echo "  Assigned 'Virtual Machine Administrator Login' to current user on PAM360 VM."
echo "  To add more users, run:"
echo "    az role assignment create --role 'Virtual Machine User Login' \\"
echo "      --assignee <user-upn> --scope <vm-resource-id>"

# ─────────────────────────────────────────────
# 4. CONDITIONAL ACCESS — require MFA for PAM360 app
#    (requires Entra ID P1 or higher; skip if on free tier)
# ─────────────────────────────────────────────
echo "[4/6] Checking Entra ID license for Conditional Access..."
SKU=$(az rest --method GET \
  --url "https://graph.microsoft.com/v1.0/subscribedSkus" \
  --query "value[].skuPartNumber" -o tsv 2>/dev/null | grep -iE "AAD_PREMIUM|P1|P2|EMS" | head -1 || true)

if [[ -n "$SKU" ]]; then
  echo "  License detected: $SKU — Conditional Access available."
  echo "  Configure MFA Conditional Access via Azure Portal:"
  echo "    Entra ID > Security > Conditional Access > New Policy"
  echo "    - Assignments: Users → All users (or target group)"
  echo "    - Cloud apps: $APP_DISPLAY_NAME"
  echo "    - Conditions: (all locations)"
  echo "    - Grant: Require MFA"
else
  echo "  No P1/P2 license detected. Conditional Access requires Entra ID P1."
  echo "  MFA can still be enforced per-user in Entra ID > Users > Per-user MFA."
fi

# ─────────────────────────────────────────────
# 5. OUTPUT — all credentials needed for PAM360 configuration
# ─────────────────────────────────────────────
echo "[5/6] Gathering SAML federation metadata..."
METADATA_URL="https://login.microsoftonline.com/${TENANT_ID}/federationmetadata/2007-06/federationmetadata.xml?appid=${APP_ID}"

echo "[6/6] Done."
echo ""
echo "============================================================"
echo " ENTRA ID CONFIGURATION SUMMARY"
echo " Save these values — required for PAM360 SSO setup"
echo "============================================================"
echo " Tenant ID         : $TENANT_ID"
echo " App (Client) ID   : $APP_ID"
echo " Client Secret     : $CLIENT_SECRET"
echo " Reply URL (ACS)   : $REPLY_URL"
echo " Logout URL        : $LOGOUT_URL"
echo " Metadata URL      : $METADATA_URL"
echo " SAML Entity ID    : https://sts.windows.net/$TENANT_ID/"
echo "============================================================"
echo ""
echo "PAM360 SAML SSO Configuration path:"
echo "  Admin > Authentication > SAML Single Sign-On"
echo "    IDP Entity ID   : https://sts.windows.net/$TENANT_ID/"
echo "    SSO URL         : https://login.microsoftonline.com/$TENANT_ID/saml2"
echo "    Logout URL      : $LOGOUT_URL"
echo "    Certificate     : Download from Entra ID App > SAML Certificates > Certificate (Base64)"
echo ""
echo "Next: Run 05-configure-jit-access.sh to enable JIT VM access"
