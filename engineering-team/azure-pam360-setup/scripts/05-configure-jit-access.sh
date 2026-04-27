#!/usr/bin/env bash
# Enable Azure Defender for Cloud JIT VM Access on endpoint VMs
# JIT access + PAM360 = dual-layer privileged access management
# Usage: bash 05-configure-jit-access.sh [--endpoint-count <n>]

set -euo pipefail

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-pam360-lab}"
SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)
ENDPOINT_COUNT="${ENDPOINT_COUNT:-2}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --endpoint-count) ENDPOINT_COUNT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo "=========================================="
echo " Configuring JIT VM Access via Defender"
echo "=========================================="

# ─────────────────────────────────────────────
# 1. ENABLE DEFENDER FOR SERVERS (required for JIT)
# ─────────────────────────────────────────────
echo "[1/3] Enabling Microsoft Defender for Servers (required for JIT)..."
az security pricing create \
  --name "VirtualMachines" \
  --tier "Standard" \
  --output table 2>/dev/null || \
  echo "  Defender for Servers already enabled or requires owner permissions."

# ─────────────────────────────────────────────
# 2. APPLY JIT POLICY TO EACH ENDPOINT VM
#    Port 3389 (RDP) locked down — opens only on approved request
# ─────────────────────────────────────────────
echo "[2/3] Applying JIT policies to endpoint VMs..."

for i in $(seq 1 "$ENDPOINT_COUNT"); do
  VM_NAME="vm-win-endpoint-$(printf '%02d' "$i")"
  VM_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$VM_NAME"

  echo "  Applying JIT policy to $VM_NAME..."

  az rest \
    --method PUT \
    --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Security/locations/$(az account list-locations --query "[?name=='$(az group show --name $RESOURCE_GROUP --query location -o tsv)'].name | [0]" -o tsv)/jitNetworkAccessPolicies/${VM_NAME}-jit?api-version=2020-01-01" \
    --body "{
      \"kind\": \"Basic\",
      \"properties\": {
        \"virtualMachines\": [
          {
            \"id\": \"$VM_ID\",
            \"ports\": [
              {
                \"number\": 3389,
                \"protocol\": \"TCP\",
                \"allowedSourceAddressPrefix\": \"10.10.1.0/24\",
                \"maxRequestAccessDuration\": \"PT4H\"
              }
            ]
          }
        ]
      }
    }" \
    --output table 2>/dev/null || \
    echo "  Note: JIT via REST failed — configure manually in Defender for Cloud > Just-in-time VM access > $VM_NAME"
done

# ─────────────────────────────────────────────
# 3. INSTRUCTIONS: HOW PAM360 REQUESTS JIT ACCESS
# ─────────────────────────────────────────────
echo "[3/3] JIT access workflow configured."
echo ""
echo "============================================================"
echo " JIT ACCESS WORKFLOW"
echo "============================================================"
echo ""
echo " Azure JIT (Defender for Cloud) — port 3389 locked by default."
echo " PAM360 requests access → JIT opens port for approved duration → PAM360 connects."
echo ""
echo " To manually approve JIT access via CLI:"
echo "   VM_ID=\"/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP\""
echo "   VM_ID+=\"/providers/Microsoft.Compute/virtualMachines/vm-win-endpoint-01\""
echo ""
echo "   az rest --method POST \\"
echo "     --url 'https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/"
echo "            resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Security/"
echo "            locations/<location>/jitNetworkAccessPolicies/vm-win-endpoint-01-jit/"
echo "            initiate?api-version=2020-01-01' \\"
echo "     --body '{"
echo "       \"virtualMachines\": [{"
echo "         \"id\": \"'\$VM_ID'\","
echo "         \"ports\": [{"
echo "           \"number\": 3389,"
echo "           \"duration\": \"PT2H\","
echo "           \"allowedSourceAddressPrefix\": \"10.10.1.10\""
echo "         }]"
echo "       }]"
echo "     }'"
echo ""
echo " PAM360 JIT integration:"
echo "   Admin > Targets > Add Target > Windows"
echo "   Enable 'Request access before connecting' to trigger JIT"
echo "============================================================"
echo ""
echo "Next: Run 06-assign-roles-users.sh to assign Entra ID users/groups to endpoints"
