---
name: azure-pam360-setup
description: Deploy and configure a ManageEngine PAM360 test lab on Azure using Azure CLI — Windows endpoint JIT access via Entra ID authentication, no Active Directory required.
---

# Azure PAM360 Lab Setup

Deploy a complete ManageEngine PAM360 Privileged Access Management test environment on Azure.
Authentication is Entra ID only — no Active Directory Domain Services required.
Windows endpoint RDP access is gated through PAM360 JIT workflows.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Resource Group: rg-pam360-lab                                  │
│  VNet: vnet-pam360 (10.10.0.0/16)                              │
│                                                                 │
│  ┌──────────────────────┐    ┌──────────────────────────────┐  │
│  │ snet-pam-server      │    │ snet-endpoints               │  │
│  │ 10.10.1.0/24         │    │ 10.10.2.0/24                 │  │
│  │                      │    │                              │  │
│  │ vm-pam360-server     │───RDP──▶ vm-win-endpoint-01      │  │
│  │ 10.10.1.10           │    │     10.10.2.10               │  │
│  │ Standard_B4ms        │    │ vm-win-endpoint-02           │  │
│  │ (public IP: HTTPS    │    │     10.10.2.11               │  │
│  │  port 8282)          │    │     Standard_B2s (no pub IP) │  │
│  └──────────────────────┘    └──────────────────────────────┘  │
│                                                                 │
│  Entra ID Auth (AADLoginForWindows) — no AD DS on any VM       │
│  NSG: Endpoints block all RDP except from 10.10.1.0/24         │
└─────────────────────────────────────────────────────────────────┘

Internet ──HTTPS:8282──▶ PAM360 console ──JIT RDP──▶ Endpoints
Users authenticate via Entra ID SAML SSO into PAM360
```

**Cost estimate (East US, 2 endpoints, running 8h/day):** ~$1.80–$2.50/day

---

## Prerequisites

- Azure CLI installed and logged in: `az login`
- Contributor or Owner role on the Azure subscription
- Entra ID account with permission to create App Registrations
- ManageEngine PAM360 installer (free trial): https://www.manageengine.com/privileged-access-management/download.html

---

## Quick Start

```bash
# 1. Clone and enter skill directory
cd engineering-team/azure-pam360-setup

# 2. Configure environment
cp assets/pam360-lab-config-template.env .env
# Edit .env and set ADMIN_PASSWORD
source .env

# 3. Run scripts in order
bash scripts/01-create-infrastructure.sh
bash scripts/02-create-pam360-vm.sh
bash scripts/03-create-endpoint-vms.sh
bash scripts/04-configure-entra-id.sh
bash scripts/05-configure-jit-access.sh

# 4. Assign your Entra ID user login rights on endpoint VMs
bash scripts/06-assign-roles-users.sh --upn you@yourdomain.com --role admin --all-endpoints

# 5. When done testing — stop all costs
bash scripts/07-teardown.sh
```

---

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `01-create-infrastructure.sh` | Resource group, VNet, subnets, NSGs, storage account |
| `02-create-pam360-vm.sh` | Windows Server 2022 VM for PAM360 server (`Standard_B4ms`) |
| `03-create-endpoint-vms.sh` | Windows endpoint VMs with no public IP (`Standard_B2s`) |
| `04-configure-entra-id.sh` | App Registration, SAML reply URLs, client secret, VM login roles |
| `05-configure-jit-access.sh` | Defender for Cloud JIT policies on endpoint ports |
| `06-assign-roles-users.sh` | Assign Entra ID VM login roles to users or groups |
| `07-teardown.sh` | Delete all resources and App Registration |

---

## VM Sizing (POC — Cheapest Viable)

| VM | Role | Size | vCPU | RAM | Est. Cost/hr |
|----|------|------|------|-----|--------------|
| vm-pam360-server | PAM360 server | Standard_B4ms | 4 | 16 GB | ~$0.17 |
| vm-win-endpoint-01/02 | Windows target | Standard_B2s | 2 | 4 GB | ~$0.04 each |

Stop VMs when not testing to eliminate compute charges:
```bash
az vm deallocate --resource-group rg-pam360-lab --name vm-pam360-server
az vm deallocate --resource-group rg-pam360-lab --name vm-win-endpoint-01
```

---

## PAM360 Post-Install Configuration

After installing PAM360 on `vm-pam360-server`:

### 1. Configure Entra ID SAML SSO

**Admin → Authentication → SAML Single Sign-On**

Use the values output by `04-configure-entra-id.sh`:
- IDP Entity ID: `https://sts.windows.net/<tenant-id>/`
- SSO URL: `https://login.microsoftonline.com/<tenant-id>/saml2`
- Certificate: Download from Entra ID → Enterprise Applications → PAM360 → Single sign-on → SAML Certificate

### 2. Add Windows Endpoints as PAM360 Targets

**Admin → Resources → Add Resource**
- Resource Type: Windows
- IP Address: `10.10.2.10` (endpoint-01), `10.10.2.11` (endpoint-02)
- Port: 3389
- Local admin credential: store in PAM360 vault (the `ADMIN_USERNAME` / `ADMIN_PASSWORD` from setup)

### 3. Enable Session Recording

**Admin → Configuration → Session Recording → Enable**

All RDP sessions through PAM360 will be recorded and available for audit.

### 4. Configure JIT Access Policy in PAM360

**Admin → Configuration → Just-in-Time Access → Enable**
- Set default access duration: 2 hours
- Require justification: Yes
- Optional: require manager approval for admin-level access

---

## Security Controls in This Lab

| Control | Implementation |
|---------|---------------|
| No direct internet RDP to endpoints | NSG blocks port 3389 from Internet on endpoint subnet |
| Entra ID-only authentication | `AADLoginForWindows` extension; no AD DS join |
| Session proxy | All RDP routed through PAM360 — no direct client-to-endpoint |
| Session recording | PAM360 records all privileged sessions |
| JIT access | Defender for Cloud JIT + PAM360 time-limited checkout |
| Credential vaulting | PAM360 stores and rotates local admin passwords |
| Audit trail | PAM360 logs all access requests, approvals, sessions |

---

## Entra ID User Workflow

```
1. User navigates to https://<pam360-fqdn>:8282
2. Clicks "Login with SSO / Azure AD"
3. Redirected to Microsoft login — authenticates with Entra ID credentials
4. PAM360 receives SAML assertion → user session created
5. User browses available Windows endpoints
6. Requests RDP access → provides justification
7. PAM360 (optionally) notifies approver
8. On approval: PAM360 opens RDP session via built-in gateway
9. Session timer visible — access revoked at expiry
10. Session recording available in audit logs
```

---

## References

- [PAM360 + Entra ID Integration Details](references/pam360-entra-id-integration.md)
- [ManageEngine PAM360 Admin Guide](https://www.manageengine.com/privileged-access-management/help/admin-guide/)
- [Azure AADLoginForWindows Extension](https://learn.microsoft.com/en-us/entra/identity/devices/howto-vm-sign-in-azure-ad-windows)
- [Defender for Cloud JIT Access](https://learn.microsoft.com/en-us/azure/defender-for-cloud/just-in-time-access-usage)
