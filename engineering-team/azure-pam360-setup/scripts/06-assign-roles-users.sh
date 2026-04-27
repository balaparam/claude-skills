#!/usr/bin/env bash
# Assign Entra ID users/groups VM login roles on endpoint VMs
# Supports: Virtual Machine Administrator Login / Virtual Machine User Login
# Usage: bash 06-assign-roles-users.sh --upn user@domain.com [--role admin|user] [--all-endpoints]

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-pam360-lab}"
ENDPOINT_COUNT="${ENDPOINT_COUNT:-2}"
ROLE="user"       # default: non-admin (RDP with standard user)
UPN=""
ALL_ENDPOINTS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upn)           UPN="$2";              shift 2 ;;
    --role)          ROLE="$2";             shift 2 ;;
    --all-endpoints) ALL_ENDPOINTS=true;    shift   ;;
    --count)         ENDPOINT_COUNT="$2";   shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$UPN" ]]; then
  echo "Usage: $0 --upn user@domain.com [--role admin|user] [--all-endpoints] [--count N]"
  echo ""
  echo "  --role admin  → 'Virtual Machine Administrator Login' (local admin on VM)"
  echo "  --role user   → 'Virtual Machine User Login' (standard user on VM)"
  exit 1
fi

case "$ROLE" in
  admin) ROLE_NAME="Virtual Machine Administrator Login" ;;
  user)  ROLE_NAME="Virtual Machine User Login" ;;
  *)     echo "ERROR: --role must be 'admin' or 'user'"; exit 1 ;;
esac

echo "=========================================="
echo " Assigning Entra ID VM Login Roles"
echo " User : $UPN"
echo " Role : $ROLE_NAME"
echo "=========================================="

# Resolve user object ID from UPN
USER_OID=$(az ad user show --id "$UPN" --query "id" -o tsv 2>/dev/null || true)
if [[ -z "$USER_OID" ]]; then
  echo "ERROR: Could not find Entra ID user with UPN: $UPN"
  echo "       Run 'az ad user list --filter \"mail eq '\''$UPN'\''\"' to verify."
  exit 1
fi
echo "  User object ID: $USER_OID"

assign_role() {
  local SCOPE="$1"
  local VM_LABEL="$2"
  az role assignment create \
    --role "$ROLE_NAME" \
    --assignee-object-id "$USER_OID" \
    --assignee-principal-type User \
    --scope "$SCOPE" \
    --output table 2>/dev/null && \
    echo "  ✓ Assigned $ROLE_NAME to $UPN on $VM_LABEL" || \
    echo "  ⚠ Role may already exist on $VM_LABEL — skipping"
}

if [[ "$ALL_ENDPOINTS" == "true" ]]; then
  for i in $(seq 1 "$ENDPOINT_COUNT"); do
    VM_NAME="vm-win-endpoint-$(printf '%02d' "$i")"
    VM_ID=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --query "id" -o tsv)
    assign_role "$VM_ID" "$VM_NAME"
  done
else
  echo ""
  echo "Available endpoint VMs:"
  for i in $(seq 1 "$ENDPOINT_COUNT"); do
    echo "  $i) vm-win-endpoint-$(printf '%02d' "$i")"
  done
  echo ""
  read -rp "Enter VM number to assign role (or 'all'): " CHOICE
  if [[ "$CHOICE" == "all" ]]; then
    for i in $(seq 1 "$ENDPOINT_COUNT"); do
      VM_NAME="vm-win-endpoint-$(printf '%02d' "$i")"
      VM_ID=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --query "id" -o tsv)
      assign_role "$VM_ID" "$VM_NAME"
    done
  else
    VM_NAME="vm-win-endpoint-$(printf '%02d' "$CHOICE")"
    VM_ID=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --query "id" -o tsv)
    assign_role "$VM_ID" "$VM_NAME"
  fi
fi

echo ""
echo "Role assignment complete."
echo ""
echo "The user '$UPN' can now authenticate to VMs via Entra ID (no AD DS required)."
echo "In PAM360, add this user under Admin > Users & Roles > Add User"
echo "and select Entra ID / SAML as the authentication method."
