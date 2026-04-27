# PAM360 + Entra ID Integration Reference

## Authentication Architecture (No Active Directory)

```
User (Browser)
     │
     ▼
PAM360 Web Console (HTTPS :8282)
     │  ──── SAML 2.0 / OAuth 2.0 ────▶  Entra ID (Azure AD)
     │                                         │
     │  ◀─── SAML Assertion + User Attrs ─────┘
     │
     ▼
PAM360 grants session  →  requests JIT access  →  RDP to Windows Endpoint
```

**Key principle**: Entra ID is the **sole identity provider**. No domain join, no AD DS, no Kerberos.

---

## PAM360 SAML SSO Configuration

Navigate: **Admin → Authentication → SAML Single Sign-On**

| PAM360 Field          | Value                                                                 |
|-----------------------|-----------------------------------------------------------------------|
| IDP Entity ID         | `https://sts.windows.net/<tenant-id>/`                               |
| SSO Login URL         | `https://login.microsoftonline.com/<tenant-id>/saml2`                |
| SSO Logout URL        | `https://login.microsoftonline.com/<tenant-id>/saml2`                |
| IDP Certificate       | Download from Entra ID App → SAML Certificates → Certificate (Base64)|
| Attribute mapping     | `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress` |

### PAM360 SAML Reply URL (paste into Entra ID App Registration)
```
https://<pam360-server-ip-or-fqdn>:8282/samlResponse
```

---

## Entra ID App Registration Settings

### Manifest changes required
In Entra ID → App Registration → Manifest, set:
```json
"requestedAccessTokenVersion": 2,
"signInAudience": "AzureADMyOrg"
```

### Required API Permissions
| API               | Permission              | Type      | Purpose                    |
|-------------------|-------------------------|-----------|----------------------------|
| Microsoft Graph   | `User.Read`             | Delegated | Read signed-in user profile|
| Microsoft Graph   | `Directory.Read.All`    | Delegated | Read Entra ID group membership |

Grant admin consent after adding permissions.

---

## VM Entra ID Login (AADLoginForWindows Extension)

The `AADLoginForWindows` extension enables Entra ID authentication directly on Windows VMs without domain join.

### Two RBAC roles control access level:

| Role                                  | Windows VM access level         |
|---------------------------------------|---------------------------------|
| `Virtual Machine Administrator Login` | Local Administrators group      |
| `Virtual Machine User Login`          | Remote Desktop Users group only |

### Assign role to a user:
```bash
az role assignment create \
  --role "Virtual Machine User Login" \
  --assignee user@contoso.com \
  --scope /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/<vm-name>
```

### Assign role to a group (recommended for teams):
```bash
GROUP_OID=$(az ad group show --group "PAM360-Operators" --query id -o tsv)
az role assignment create \
  --role "Virtual Machine User Login" \
  --assignee-object-id "$GROUP_OID" \
  --assignee-principal-type Group \
  --scope /subscriptions/<sub-id>/resourceGroups/<rg>
```

---

## JIT Access Flow

```
1. User logs into PAM360 with Entra ID credentials (SAML SSO)
2. User requests access to a Windows endpoint in PAM360
3. PAM360 checks approval workflow (optional: manager approval)
4. PAM360 opens an RDP connection via its built-in gateway to the endpoint
5. Session is recorded (session recording enabled by default)
6. Access automatically revoked after the approved duration
```

### PAM360 Target Configuration (Windows endpoint):
- **Admin → Targets → Add Resource → Windows**
- Connection type: RDP
- IP Address: private IP of endpoint VM (e.g., `10.10.2.10`)
- Authentication: Local account stored in PAM360 vault (not Entra ID directly)
- Password rotation: Enable automatic rotation after each checkout

---

## Network Flow Summary

```
Internet  →  PAM360 Public IP :8282 (HTTPS web console)
                                │
PAM360 VM (10.10.1.10)  ────RDP──▶  Endpoint VMs (10.10.2.x)
                         Port 3389 (JIT-gated by NSG + Defender)

Endpoints have NO public IP — unreachable from internet directly.
```

---

## PAM360 Minimum System Requirements

| Component        | Minimum (POC)         | Recommended (Prod)    |
|------------------|-----------------------|-----------------------|
| CPU              | 4 cores               | 8 cores               |
| RAM              | 8 GB                  | 16 GB                 |
| Disk             | 50 GB                 | 100 GB+               |
| OS               | Windows Server 2016+  | Windows Server 2022   |
| Java             | Bundled with installer| Bundled               |
| Port             | 8282 (HTTPS)          | 443 (reverse proxy)   |

**Azure VM for POC:** `Standard_B4ms` (4 vCPU, 16 GB, ~$0.17/hr)

---

## PAM360 Download & Install

1. Download: https://www.manageengine.com/privileged-access-management/download.html
2. Run installer as Administrator on `vm-pam360-server`
3. Accept default port 8282 or change as needed
4. On first launch: `https://localhost:8282`
5. Default login: `admin` / `admin` — **change immediately**

---

## Troubleshooting

| Issue                              | Check                                                         |
|------------------------------------|---------------------------------------------------------------|
| SAML login fails                   | Verify Reply URL matches exactly in both PAM360 and Entra ID  |
| VM login rejected with Entra ID    | Confirm `AADLoginForWindows` extension is installed           |
| RDP fails from PAM360 to endpoint  | Check NSG rule allows `10.10.1.0/24` on port 3389 to endpoint|
| JIT access not working             | Ensure Defender for Servers (Standard) is enabled on endpoint |
| PAM360 can't reach endpoint        | Ping `10.10.2.x` from PAM360 VM — check VNet peering/routing |
