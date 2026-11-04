# Amazon Connect + Azure AD (Microsoft Entra ID) Integration Guide

This document describes how to configure Amazon Connect with SAML-based identity federation using Microsoft Entra ID (formerly Azure AD). It covers the complete setup for agent authentication and automated user provisioning via SCIM.

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [AWS IAM Configuration](#3-aws-iam-configuration)
4. [Azure AD Enterprise Applications](#4-azure-ad-enterprise-applications)
5. [SAML Claims Configuration](#5-saml-claims-configuration)
6. [Connect Instance Configuration](#6-connect-instance-configuration)
7. [User Provisioning (SCIM)](#7-user-provisioning-scim)
8. [Post-Provisioning Automation](#8-post-provisioning-automation)
9. [Operational Procedures](#9-operational-procedures)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Overview

### What This Integration Enables

- **Single Sign-On (SSO)**: Users authenticate via Microsoft Entra ID and are federated into Amazon Connect without needing separate credentials
- **Centralized Identity Management**: All user lifecycle operations (create, update, delete) are managed in Azure AD
- **Automatic User Provisioning**: SCIM synchronizes users from Azure AD to Amazon Connect
- **No Password Management in Connect**: Passwords are entirely managed by Entra ID

### Key Concepts

| Concept | Description |
|---------|-------------|
| SAML Federation | Users authenticate with Azure AD, which sends a SAML assertion to AWS; AWS trusts this assertion and grants access to Connect |
| Enterprise Application | An Azure AD application that represents Amazon Connect; users are assigned to this app to gain access |
| SCIM (System for Cross-domain Identity Management) | Protocol for automatic user provisioning between Azure AD and Amazon Connect |
| Relay State | URL that determines where the user lands after SAML authentication (Management Console vs Agent Workspace) |
| RoleSessionName | SAML attribute that MUST match the Connect username exactly (case-sensitive) |

---

## 2. Architecture

### Authentication Flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                           SAML Authentication Flow                            │
│                                                                              │
│  ┌─────────┐    ┌───────────────┐    ┌─────────────┐    ┌─────────────────┐ │
│  │  User   │───►│ My Apps Portal│───►│  Azure AD   │───►│   AWS STS       │ │
│  │         │    │ (myapps.      │    │ (SAML IdP)  │    │ (AssumeRoleWith │ │
│  │         │    │  microsoft.   │    │             │    │  SAML)          │ │
│  │         │    │  com)         │    │             │    │                 │ │
│  └─────────┘    └───────────────┘    └─────────────┘    └────────┬────────┘ │
│                                                                   │          │
│                                                                   ▼          │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                         Amazon Connect Instance                         ││
│  │  ┌───────────────────────────┐    ┌──────────────────────────────────┐ ││
│  │  │   Management Console      │    │     Agent Workspace (CCP)        │ ││
│  │  │   (Admins/Supervisors)    │    │     (Agents)                     │ ││
│  │  │   destination=%2Fconnect  │    │     destination=%2Fagent-app-v2  │ ││
│  │  └───────────────────────────┘    └──────────────────────────────────┘ ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────────┘
```

### User Provisioning Flow (SCIM)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        SCIM User Provisioning Flow                           │
│                                                                              │
│  ┌──────────────┐                                                            │
│  │  Azure AD    │                                                            │
│  │  Admin adds  │                                                            │
│  │  user to     │                                                            │
│  │  group       │                                                            │
│  └──────┬───────┘                                                            │
│         │                                                                    │
│         ▼                                                                    │
│  ┌──────────────────┐    ┌─────────────────────────────────────────────────┐│
│  │ SCIM Provisioning│    │              Amazon Connect                     ││
│  │ (up to 40 min    │───►│  Creates user with:                             ││
│  │  cycle)          │    │  - Username = user.userprincipalname            ││
│  │                  │    │  - Security Profile = "Agente" (default)        ││
│  │                  │    │  - Routing Profile = Default RP                 ││
│  └──────────────────┘    └──────────────────────┬──────────────────────────┘│
│                                                  │                           │
│                                                  ▼                           │
│  ┌──────────────────────────────────────────────────────────────────────────┐│
│  │           Post-Provisioning Lambda Automation                            ││
│  │  - Creates per-agent Routing Profile                                     ││
│  │  - Assigns user to hierarchy group                                       ││
│  │  - Triggered by EventBridge (CreateUser event)                           ││
│  └──────────────────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. AWS IAM Configuration

### 3.1 Create SAML Identity Providers

Create two SAML providers in IAM - one for admin/supervisor access and one for agent access:

```yaml
# CloudFormation snippet for SAML providers
Resources:
  SAMLProviderAdmin:
    Type: AWS::IAM::SAMLProvider
    Properties:
      Name: !Sub "connect-identity-provider-admin-${Environment}"
      SamlMetadataDocument: !Ref AdminSAMLMetadataDocument

  SAMLProviderAgent:
    Type: AWS::IAM::SAMLProvider
    Properties:
      Name: !Sub "connect-identity-provider-agent-${Environment}"
      SamlMetadataDocument: !Ref AgentSAMLMetadataDocument
```

**To get the SAML Metadata Document:**
1. In Azure AD, go to Enterprise Applications → Your App → Single Sign-On
2. Download the Federation Metadata XML
3. Use this XML as the `SamlMetadataDocument` value

### 3.2 Create Federation Role

Create an IAM role that Azure AD users will assume:

```yaml
Resources:
  ConnectFederationRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub "connect-federation-role-${Environment}"
      AssumeRolePolicyDocument:
        Version: "2012-10-17"
        Statement:
          - Effect: Allow
            Principal:
              Federated: 
                - !GetAtt SAMLProviderAdmin.Arn
                - !GetAtt SAMLProviderAgent.Arn
            Action: "sts:AssumeRoleWithSAML"
            Condition:
              StringEquals:
                "SAML:aud": "https://signin.aws.amazon.com/saml"
      Policies:
        - PolicyName: ConnectFederationPolicy
          PolicyDocument:
            Version: "2012-10-17"
            Statement:
              - Effect: Allow
                Action:
                  - "connect:GetFederationToken"
                Resource: !Sub "arn:aws:connect:${AWS::Region}:${AWS::AccountId}:instance/${ConnectInstanceId}/user/*"
```

### 3.3 Resource Summary Per Environment

| Environment | IAM Federation Role | SAML Provider (Admin) | SAML Provider (Agent) |
|-------------|--------------------|-----------------------|----------------------|
| Dev | `arn:aws:iam::<account>:role/connect-federation-role-dev` | `arn:aws:iam::<account>:saml-provider/connect-identity-provider-admin-dev` | `arn:aws:iam::<account>:saml-provider/connect-identity-provider-agent-dev` |
| QA | `arn:aws:iam::<account>:role/connect-federation-role-qa` | `arn:aws:iam::<account>:saml-provider/connect-identity-provider-admin-qa` | `arn:aws:iam::<account>:saml-provider/connect-identity-provider-agent-qa` |
| Prod | `arn:aws:iam::<account>:role/connect-federation-role-prod` | `arn:aws:iam::<account>:saml-provider/connect-identity-provider-admin-prod` | `arn:aws:iam::<account>:saml-provider/connect-identity-provider-agent-prod` |

---

## 4. Azure AD Enterprise Applications

### 4.1 Create Enterprise Applications

Create separate Enterprise Applications for different access types:

| Environment | App Name | Purpose |
|-------------|----------|---------|
| Dev | Amazon Connect - DEV | Management Console only (technical users) |
| QA | Amazon Connect - QA (Management Console) | Admin/supervisor console access |
| QA | Amazon Connect - QA (Agent Workspace) | Agent CCP access |
| Prod | Amazon Connect - PROD (Management Console) | Admin/supervisor console access |
| Prod | Amazon Connect - PROD (Agent Workspace) | Agent CCP access |

### 4.2 Basic SAML Settings

For each Enterprise Application, configure:

| Setting | Value |
|---------|-------|
| Entity ID (Identifier) | `https://signin.aws.amazon.com/saml#<unique-suffix>` |
| Reply URL (ACS) | `https://signin.aws.amazon.com/saml` |
| Sign-on URL | Leave empty |
| Relay State | See section 4.3 |

**Note:** Each Enterprise Application needs a unique Entity ID suffix (e.g., `#1`, `#2`, etc.) to differentiate them within the same tenant.

### 4.3 Relay State URLs

The Relay State URL determines where the user lands after authentication:

| Destination | Relay State Format |
|-------------|-------------------|
| Management Console | `https://<region>.console.aws.amazon.com/connect/federate/<instance-id>?destination=%2Fconnect` |
| Agent Workspace (CCP) | `https://<region>.console.aws.amazon.com/connect/federate/<instance-id>?destination=%2Fagent-app-v2` |

**Example for us-east-1:**
```
# Management Console
https://us-east-1.console.aws.amazon.com/connect/federate/6c178974-c178-45c9-a701-29242aa430fe?destination=%2Fconnect

# Agent Workspace
https://us-east-1.console.aws.amazon.com/connect/federate/6c178974-c178-45c9-a701-29242aa430fe?destination=%2Fagent-app-v2
```

### 4.4 Azure AD Groups

Create dedicated Azure AD groups to control access:

| Environment | Group Purpose | Assigned Enterprise App |
|-------------|---------------|------------------------|
| Dev | Technical users | Amazon Connect - DEV |
| QA | Admin/supervisors | Amazon Connect - QA (Management Console) |
| QA | Agents | Amazon Connect - QA (Agent Workspace) |
| Prod | Admin/supervisors | Amazon Connect - PROD (Management Console) |
| Prod | Agents | Amazon Connect - PROD (Agent Workspace) |

Assign these groups to their corresponding Enterprise Applications under "Users and groups".

---

## 5. SAML Claims Configuration

### 5.1 Required Claims

Configure these claims in each Enterprise Application under Single Sign-On → Attributes & Claims:

| Claim Name (Full URI) | Source Attribute | Purpose |
|-----------------------|------------------|---------|
| Unique User Identifier (Name ID) | `user.userprincipalname` | Identifies the user |
| `https://aws.amazon.com/SAML/Attributes/RoleSessionName` | `user.userprincipalname` | **MUST match Connect username exactly** |
| `https://aws.amazon.com/SAML/Attributes/SessionDuration` | `900` (constant) | STS credential duration (in seconds) |
| `https://aws.amazon.com/SAML/Attributes/Role` | See format below | IAM role + SAML provider ARNs |

### 5.2 Role Claim Format

The Role claim must contain the IAM role ARN and SAML provider ARN separated by a comma:

```
arn:aws:iam::<account>:role/connect-federation-role-<env>,arn:aws:iam::<account>:saml-provider/connect-identity-provider-<admin|agent>-<env>
```

**Examples:**
```
# Admin/Management Console app
arn:aws:iam::344501434542:role/connect-federation-role-prod,arn:aws:iam::344501434542:saml-provider/connect-identity-provider-admin-prod

# Agent Workspace app
arn:aws:iam::344501434542:role/connect-federation-role-prod,arn:aws:iam::344501434542:saml-provider/connect-identity-provider-agent-prod
```

### 5.3 Session Duration Note

The `SessionDuration` attribute (900 seconds = 15 minutes) controls the AWS STS temporary credentials duration only. Amazon Connect ignores this value and always enforces a **12-hour session** after login.

---

## 6. Connect Instance Configuration

### 6.1 CloudFormation Template

Configure the Connect instance with SAML identity management:

```yaml
Parameters:
  IdentityManagementType:
    Type: String
    Default: SAML
    AllowedValues: [SAML, CONNECT_MANAGED, EXISTING_DIRECTORY]

Resources:
  ConnectInstance:
    Type: AWS::Connect::Instance
    Properties:
      InstanceAlias: !Ref ConnectInstanceAlias
      IdentityManagementType: !Ref IdentityManagementType
      Attributes:
        InboundCalls: "true"
        OutboundCalls: "true"
        ContactLens: "true"
        EnhancedContactMonitoring: "true"
        ContactflowLogs: "true"
        EarlyMedia: "true"
        AutoResolveBestVoices: "true"
```

### 6.2 Important Instance Attributes

| Attribute | Value | Description |
|-----------|-------|-------------|
| IdentityManagementType | `SAML` | Enables SAML-based federation |
| InboundCalls | `true` | Enable inbound calls |
| OutboundCalls | `true` | Enable outbound calls |
| ContactLens | `true` | Enable Contact Lens analytics |

### 6.3 Access Behavior

- **No direct access**: Users cannot log in directly at the Connect instance URL (`https://<alias>.my.connect.aws/`)
- **Only via My Apps portal**: Users must access Connect through the Azure AD My Apps portal which triggers the SAML flow
- **Direct URL behavior**: Visiting the instance URL directly shows "Session Expired" (expected behavior)

---

## 7. User Provisioning (SCIM)

### 7.1 Prerequisites

For a user to access Amazon Connect, TWO conditions must be met:

1. **Azure AD group membership**: User must be in the group assigned to the Enterprise Application
2. **User exists in Connect**: User must exist in Amazon Connect with username = `user.userprincipalname`

### 7.2 Initial User Load (CSV Bulk Upload)

For initial go-live, use CSV bulk upload with the SAML-specific template:

| Column | Description |
|--------|-------------|
| first name | User's first name |
| last name | User's last name |
| user login | **Must match** `user.userprincipalname` from Azure AD (case-sensitive) |
| routing profile name | Name of the routing profile to assign |
| security_profile_name_1 | Primary security profile |
| user hierarchy | Hierarchy path (e.g., "Division/Group") |
| phone type | Usually "SOFT_PHONE" |

**Note:** SAML CSV template does NOT include email or password columns - passwords are managed by Azure AD.

### 7.3 SCIM Configuration

Enable SCIM on the **Agent Workspace** Enterprise Application (not the Management Console app):

1. Go to Enterprise Application → Provisioning
2. Set Provisioning Mode to "Automatic"
3. Configure Admin Credentials:
   - **Tenant URL**: SCIM endpoint from Connect (see below)
   - **Secret Token**: Generate from Connect admin console

**Getting SCIM credentials from Connect:**
1. Amazon Connect Admin Console → Security profiles
2. Click on any security profile → Actions → "Configure SCIM"
3. Copy the SCIM endpoint URL and generate a bearer token

### 7.4 What SCIM Provisions

| Attribute | Provisioned? | Notes |
|-----------|--------------|-------|
| Username | ✅ Yes | From `user.userprincipalname` |
| First name | ✅ Yes | From Azure AD profile |
| Last name | ✅ Yes | From Azure AD profile |
| Security profile | ✅ Yes (default) | Always creates with default profile |
| Routing profile | ✅ Yes (default) | Uses instance default RP |
| Hierarchy group | ❌ No | Must be assigned separately |
| Phone type | ❌ No | Uses default (soft phone) |

### 7.5 What SCIM Does NOT Do

- Does not assign custom hierarchy groups
- Does not create per-agent routing profiles
- Does not set custom security profiles
- Does not manage passwords (SAML-federated users have no password in Connect)
- **Does deprovision users**: Removing a user from the Azure AD group triggers `DeleteUser` in Connect

### 7.6 SCIM Configuration Per Environment

| Environment | SCIM Enabled | Notes |
|-------------|--------------|-------|
| Dev | ❌ No | Technical users created manually |
| QA | ✅ Yes | On Agent Workspace app |
| Prod | ✅ Yes | On Agent Workspace app |

---

## 8. Post-Provisioning Automation

### 8.1 Why Automation is Needed

SCIM creates users with default settings only. Post-provisioning automation bridges the gap between "create with defaults" and the agent's actual operational configuration.

### 8.2 Lambda Function

Create a Lambda function triggered by EventBridge when a new user is created:

```python
# Triggered by: EventBridge rule matching Connect CreateUser events
# Actions:
# 1. Creates a dedicated per-agent routing profile
# 2. Assigns user to correct hierarchy group (from mapping CSV)
# 3. Updates user to use the new routing profile
```

### 8.3 EventBridge Rule

```yaml
Resources:
  CreateUserEventRule:
    Type: AWS::Events::Rule
    Properties:
      EventPattern:
        source:
          - aws.connect
        detail-type:
          - "Amazon Connect User Created"
        detail:
          instanceArn:
            - !GetAtt ConnectInstance.Arn
      Targets:
        - Arn: !GetAtt RoutingProfileProvisioningLambda.Arn
          Id: "ProvisionRoutingProfile"
```

### 8.4 Routing Profile Mapping

Maintain a CSV mapping file (bundled with the Lambda) that maps user emails to:
- Queue assignments
- Hierarchy group
- Any custom settings

---

## 9. Operational Procedures

### 9.1 Adding a New Agent

1. **Add user to Azure AD group** assigned to the Agent Workspace Enterprise Application
2. **Wait for SCIM cycle** (up to 40 minutes) - user is created in Connect with:
   - Security profile: Default (e.g., "Agente")
   - Routing profile: Default RP (replaced by automation)
   - Hierarchy: Unassigned
3. **Post-provisioning automation** creates per-agent RP and assigns hierarchy
4. **Manual configuration** (if needed):
   - Change security profile for supervisors/coordinators
   - Assign to correct hierarchy if automation mapping is incomplete
   - Configure queue assignments

### 9.2 Removing an Agent

1. **Remove user from Azure AD group**
2. **SCIM deletes user from Connect**
3. Agent can no longer log in
4. Historical data (CTRs, recordings) is preserved

### 9.3 Promoting an Agent to Supervisor

1. **Add user to Management Console group** (they keep Agent Workspace access too)
2. **Change security profile** in Connect from "Agente" to "Coordinador" or equivalent
3. User now has access to both apps

### 9.4 Troubleshooting Access Issues

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| "Access Denied" after SAML login | Username mismatch | Verify Connect username = `user.userprincipalname` (case-sensitive) |
| "Session Expired" when visiting instance URL directly | Expected behavior | User must access via My Apps portal |
| User not appearing in Connect | SCIM cycle not complete | Wait up to 40 minutes; check SCIM provisioning logs in Azure AD |
| User in Connect but can't log in | Not in Azure AD group | Add user to correct group |

---

## 10. Troubleshooting

### 10.1 Common Issues

#### Username Case Sensitivity
The Connect username MUST exactly match `user.userprincipalname` from Azure AD, including case. If `john.doe@company.com` is in Azure AD but Connect has `John.Doe@company.com`, login will fail.

#### SAML Certificate Expiration
Azure AD SAML certificates expire. Set calendar reminders to:
1. Generate new certificate in Azure AD
2. Download new Federation Metadata XML
3. Update the IAM SAML Provider with new metadata

#### SCIM Sync Issues
Check Azure AD Provisioning logs:
1. Enterprise Application → Provisioning → Provisioning logs
2. Look for failed operations
3. Common issues: duplicate users, validation errors

### 10.2 Useful Endpoints

| Purpose | URL Format |
|---------|------------|
| My Apps Portal | `https://myapps.microsoft.com` |
| Specific App Launch | `https://launcher.myapps.microsoft.com/api/signin/<app-id>?tenantId=<tenant-id>` |
| Connect Instance | `https://<alias>.my.connect.aws/` (requires SAML flow) |

### 10.3 Testing Checklist

- [ ] SAML metadata uploaded to IAM provider
- [ ] IAM role trust policy includes both SAML providers
- [ ] Enterprise App has correct Entity ID and ACS URL
- [ ] Relay State URL has correct instance ID and destination
- [ ] Role claim has correct IAM role + SAML provider ARNs
- [ ] RoleSessionName claim maps to `user.userprincipalname`
- [ ] Test user exists in Connect with matching username
- [ ] Test user is in correct Azure AD group
- [ ] SCIM provisioning enabled (QA/Prod only)
- [ ] Post-provisioning Lambda deployed and triggered

---

## Appendix: Reference Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Complete Integration Architecture                         │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        Microsoft Entra ID                            │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │   │
│  │  │ Azure AD Groups │  │ Enterprise Apps │  │ SCIM Provisioning│     │   │
│  │  │ - Admins        │  │ - Mgmt Console  │  │ - User sync      │     │   │
│  │  │ - Agents        │  │ - Agent Workspace│ │ - 40 min cycle   │     │   │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│                           SAML Assertion                                    │
│                                    ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                            AWS Account                               │   │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │   │
│  │  │ IAM SAML        │  │ IAM Role        │  │ Amazon Connect  │     │   │
│  │  │ Providers       │  │ Federation Role │  │ Instance        │     │   │
│  │  │ - Admin provider│  │ - Trusts SAML   │  │ - SAML identity │     │   │
│  │  │ - Agent provider│  │ - connect:Get-  │  │ - Users         │     │   │
│  │  │                 │  │   FederationToken│  │ - Queues        │     │   │
│  │  └─────────────────┘  └─────────────────┘  │ - Routing       │     │   │
│  │                                            │ - Security      │     │   │
│  │                                            │   Profiles      │     │   │
│  │                                            └─────────────────┘     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

**Document Version:** 1.0  
**Last Updated:** November 2026  
**Based on:** Itaú Colombia Amazon Connect implementation
 