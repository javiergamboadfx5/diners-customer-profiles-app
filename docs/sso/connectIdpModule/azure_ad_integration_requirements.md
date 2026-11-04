# Amazon Connect - Azure AD (Entra ID) Integration Requirements

This document describes the client-facing requirements for integrating Amazon Connect with Azure AD (Microsoft Entra ID). It covers SSO authentication via SAML 2.0 and automated user provisioning via SCIM. Use this as a template when scoping IdP integration for new engagements.

---

## 1. SSO Authentication (SAML 2.0)

### Enterprise Application Strategy: Two Apps per Environment

We recommend creating **2 Enterprise Applications per environment** (e.g., 2 for Dev, 2 for QA, 2 for Prod):

| Enterprise Application | Purpose | Relay State Destination |
|------------------------|---------|------------------------|
| **Amazon Connect - Management Console** | For administrators and supervisors who need access to the Connect admin console (routing configuration, user management, reporting dashboards, etc.) | Connect management console |
| **Amazon Connect - Agent Workspace** | For agents and supervisors who handle contacts through the agent interface (CCP, Customer Profiles, Cases, etc.) | Agent Workspace (`/connect/agent-app-v2`) |

This separation allows the client to:
- Control access independently - not every agent needs console access, and not every admin needs the agent workspace
- Assign different user groups to each application in Azure AD
- Apply different Conditional Access policies per application if needed (e.g., stricter MFA for management console)

Both applications share the same IAM SAML Identity Provider and Federation Role on the AWS side. The only difference is the **Relay State URL** that determines where the user lands after authentication.

### What DFX5 Delivers

- IAM SAML Identity Provider configuration in the AWS account
- IAM Federation Role for SAML assertion trust
- Relay State URLs for both Enterprise Applications (management console + agent workspace)
- SAML attribute mapping specification

### What the Client Needs to Provide

| Item | Description |
|------|-------------|
| **2 Azure AD Enterprise Applications per environment** | Create two Enterprise Applications (non-gallery / SAML) in their Azure AD tenant - one for management console access, one for agent workspace access |
| **SAML Metadata XML** | Export the Federation Metadata XML from each Enterprise Application and share with DFX5. Note: if both apps use the same signing certificate, a single metadata file may suffice |
| **User/Group Assignment** | Assign the appropriate users or groups to each Enterprise Application based on their role (admin/supervisor vs. agent) |

### SAML Attribute Mapping (Client configures in Azure AD)

The following SAML claims must be configured in **both** Enterprise Applications. In Azure AD's
**Attributes & Claims** editor each claim splits across two fields: put `https://aws.amazon.com/SAML/Attributes`
in **Namespace** and just the short name (`RoleSessionName`, `SessionDuration`, `Role`) in **Name** -
Azure AD joins them into the full claim name. Putting the full claim name in **Name** with
**Namespace** left blank sends a different claim and AWS won't see it.

| Claim Name | Source Attribute | Notes |
|------------|-----------------|-------|
| `https://aws.amazon.com/SAML/Attributes/RoleSessionName` | `user.userprincipalname` | Identifies the user session |
| `https://aws.amazon.com/SAML/Attributes/SessionDuration` | `900` (constant) | Session duration in seconds |
| `https://aws.amazon.com/SAML/Attributes/Role` | ARN of SAML Provider + ARN of Federation Role | DFX5 provides these ARNs after deployment |

### Azure AD Application Configuration (Client configures)

Both Enterprise Applications share the same base configuration, differing only in the Relay State:

| Setting | Value |
|---------|-------|
| Identifier (Entity ID) | `https://signin.aws.amazon.com/saml#<unique-number>` (must be unique per application) |
| Reply URL (ACS URL) | `https://signin.aws.amazon.com/saml` |
| Relay State (Management Console) | `https://<region>.console.aws.amazon.com/connect/federate/<instance-id>` |
| Relay State (Agent Workspace) | `https://<region>.console.aws.amazon.com/connect/federate/<instance-id>?destination=%2Fconnect%2Fagent-app-v2` |

---

## 2. Automated User Provisioning (SCIM)

### What DFX5 Delivers

- SCIM-compliant API endpoint (API Gateway + Lambda)
- API authorization token (stored in AWS Secrets Manager)
- Automated user lifecycle management: create, update security profiles, deactivate
- Default routing profile and phone configuration (softphone)

### What the Client Needs to Provide / Configure

| Item | Description |
|------|-------------|
| **Enable Provisioning** | In the Enterprise Application, enable "Provisioning" and set mode to "Automatic" |
| **Tenant URL** | DFX5 provides the SCIM endpoint URL (CloudFormation output) |
| **Secret Token** | DFX5 provides the API token from AWS Secrets Manager |
| **Disable Group Provisioning** | In Provisioning > Mappings, **disable** "Provision Microsoft Entra ID Groups" (critical - see section below) |
| **User Attribute Mapping** | Configure the `department` attribute mapping as described below (only for Option A) |
| **User Attribute Population** | Populate the chosen source attribute for each user with the corresponding Connect security profile name(s) (only for Option A) |

### User Attribute Mapping for Security Profiles (Option A only)

In the Azure AD Provisioning Mappings for Users, the client must add or modify the following mapping:

| Target Attribute (SCIM) | Source Attribute (Azure AD) | Notes |
|--------------------------|----------------------------|-------|
| `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User:department` | User attribute of choice (e.g., `department`, `extensionAttribute1`, etc.) | Must contain the Connect security profile name(s) |

**The source attribute value must match exactly** one of the predefined Connect security profile names. If a user needs multiple security profiles, the values should be comma-separated (e.g., `Supervisor_AWSConnect,Agente_AWSConnect`).

---

## 3. Why User Attributes Instead of Groups for SCIM

### The Limitation

When using Azure AD SCIM provisioning with a custom SCIM endpoint (non-gallery application), **group membership information is not included in the SCIM user provisioning events**. This means:

- When Azure AD provisions or updates a user via SCIM, it sends user attributes only
- There is no reliable mechanism to receive group membership changes through SCIM provisioning events from Azure AD
- Azure AD does support SCIM Group operations (`/Groups` endpoint), but these do not carry the context needed to map a user to an Amazon Connect security profile in real-time

### The Workaround (Option A: Attribute-based)

Instead of relying on group membership, we use a **user attribute** (mapped to the SCIM `department` field) to define which Amazon Connect security profile(s) a user should receive:

1. The client populates a user attribute in Azure AD with the security profile name (e.g., `Agente_AWSConnect`)
2. Azure AD sends this attribute value during SCIM provisioning
3. The Lambda function reads the attribute and assigns the corresponding security profile in Connect

### What This Means for the Client

- The client needs to decide **which Azure AD user attribute** will hold the Connect security profile assignment (e.g., `department`, `jobTitle`, or a custom extension attribute like `extensionAttribute1`)
- This attribute must be **populated for every user** who will be provisioned to Amazon Connect
- When a user's role changes (e.g., from Agent to Supervisor), **the attribute value must be updated** in Azure AD, and the SCIM sync will propagate the change to Connect
- If the client prefers to manage access via Azure AD groups, they can use Azure AD automation (e.g., dynamic groups + Logic Apps) to keep the user attribute in sync with group membership, but the SCIM provisioning itself will always read from the user attribute

### Alternative: Simplified Provisioning with Default Profile (Option B)

If managing user attributes in Azure AD introduces too much operational complexity (e.g., large number of users, no easy way to populate/maintain the attribute, or multiple teams involved), there is a simpler alternative:

**Option B: Provision all users with a default Agent security profile**

- SCIM provisioning creates every user in Connect with a default security profile (e.g., Agent)
- No user attribute mapping is required in Azure AD
- After provisioning, a supervisor or admin manually assigns the correct security profile within the Connect management console

**Trade-offs:**

| | Option A: Attribute-based | Option B: Default profile + manual assignment |
|---|---|---|
| **Azure AD complexity** | Higher - requires attribute population and mapping | Lower - no attribute management needed |
| **Operational effort** | Automated - profile changes flow from Azure AD | Manual - supervisors must reassign profiles after provisioning |
| **Day-2 maintenance** | Role changes handled via attribute update in Azure AD | Role changes handled manually in Connect |
| **Risk of misconfiguration** | Lower once set up - single source of truth in IdP | Higher - profiles could drift if manual steps are missed |
| **Best for** | Organizations with mature Azure AD attribute management | Fast initial rollout, smaller teams, or when Azure AD admin access is limited |

Both options can coexist: start with Option B for initial rollout and migrate to Option A once the client's Azure AD team is ready to manage the attribute.

### Comparison: Azure AD vs. Okta

For reference, Okta supports real-time group membership events via Event Hooks, which allows direct group-to-security-profile mapping. Azure AD's SCIM implementation does not offer an equivalent mechanism, which is why the user attribute approach (Option A) or default profile approach (Option B) is necessary.

---

## 4. User Lifecycle Summary

### Option A: Attribute-based provisioning

| Event | Azure AD Action | Connect Result |
|-------|----------------|----------------|
| User assigned to Enterprise App | SCIM POST (create) | User created in Connect with security profile from attribute |
| User attribute updated | SCIM PATCH (update) | Security profile updated in Connect |
| User removed from Enterprise App | SCIM PATCH (active=false) | User deleted from Connect |

### Option B: Default profile provisioning

| Event | Azure AD Action | Connect Result |
|-------|----------------|----------------|
| User assigned to Enterprise App | SCIM POST (create) | User created in Connect with default Agent profile |
| Supervisor assigns profile | N/A (manual in Connect) | Security profile updated by supervisor |
| User removed from Enterprise App | SCIM PATCH (active=false) | User deleted from Connect |

---

## 5. Decisions Needed from Client

1. **Security profile provisioning approach** - Option A (attribute-based, fully automated) or Option B (default profile, manual assignment by supervisors)?
2. **If Option A: Which Azure AD attribute** will be used for security profile assignment?
   - Recommendation: `extensionAttribute1` or similar custom attribute to avoid conflicts with existing attribute usage
3. **Security profile names and mapping** to the client's operational roles (Agent, Supervisor, QA, Admin, etc.)
4. **Who will configure the Azure AD Enterprise Applications?** (client's Azure AD admin team)
5. **IP allowlisting** - Does the client require the SCIM API endpoint to be restricted to specific IP ranges? If so, provide the Azure AD outbound IP ranges for their tenant
6. **SCIM provisioning sync frequency** - Azure AD default is ~40 minutes for incremental sync. Is this acceptable, or does the client need near-real-time provisioning?

---

## 6. Prerequisites Checklist

### Client Side

- [ ] Azure AD tenant with admin access to create Enterprise Applications
- [ ] Azure AD P1 or P2 license (required for automatic provisioning)
- [ ] Identified Azure AD admin who will configure SSO and provisioning
- [ ] 2 Enterprise Applications created per environment (management console + agent workspace)
- [ ] SAML claims configured in both Enterprise Applications
- [ ] User/group assignment to each Enterprise Application based on role
- [ ] Decision on security profile provisioning approach (Option A or B)
- [ ] If Option A: users populated with the chosen attribute value
- [ ] SCIM provisioning enabled on the appropriate Enterprise Application
- [ ] Network/firewall rules allowing Azure AD to reach AWS API Gateway endpoint

### DFX5 Side

- [ ] Amazon Connect instance deployed
- [ ] Security profiles created in Connect matching the agreed naming convention
- [ ] SAML Identity Provider and Federation Role deployed (CloudFormation)
- [ ] SCIM integration stack deployed (CloudFormation)
- [ ] SCIM endpoint URL and API token shared securely with client
- [ ] Relay State URLs generated for both applications (management console + agent workspace)
