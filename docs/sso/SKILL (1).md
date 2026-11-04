---
name: enable-saml-integration
description: Set up SAML 2.0 single sign-on for an Amazon Connect instance with this repo's pre-built-assets/connect-idp-module - deploys its federation stack standalone (two IAM SAML identity providers, admin and agent, plus one federation role scoped to the instance), then walks the user through the IdP side (Microsoft Entra ID, Okta, IAM Identity Center or another SAML IdP: two applications, claims, relay states), loads the real IdP metadata, creates a matching Connect user and tests the sign-in. Use when asked to enable, set up or configure SAML, SSO, single sign-on, federation, Entra ID / Azure AD, Okta or Identity Center login for a Connect instance.
---

# Enable SAML sign-in for a Connect instance

A Connect instance with `IdentityManagementType: SAML` (in this repo's `stacks/`, the
`IdentityManagementType=SAML` parameter) has no login until federation is set up. DFX5 always does this with
[`pre-built-assets/connect-idp-module/`](../../../pre-built-assets/connect-idp-module/), never
with hand-written `AWS::IAM::SAMLProvider` or federation role resources. Its
`template_idp_integration.yaml` creates:

- Two IAM SAML identity providers: `<prefix>-identity-provider-admin-<env>` and
  `<prefix>-identity-provider-agent-<env>`, one per IdP application.
- One federation role, `<prefix>-federation-role-<env>`, trusted by both providers, allowed only
  `connect:GetFederationToken` on this instance's users.
- Outputs: the `Role` claim value for each application (`AdminSAMLRole`, `AgentSAMLRole`) and the
  relay state URLs (`AmazonConnectManagementConsoleRelayState`, `AmazonConnectAgentWorkspaceRelayState`).

It deploys as its **own stack**, not inside the root stack: the providers belong to the IdP
relationship and must survive root stack changes. It ships with placeholder metadata, so it can be
deployed before the client's IdP is ready; the real metadata is loaded in step 5.

The IdP side is usually done by the **client's IdP admin**, not by us. Go step by step: explain
the step, do it (or give the user exactly what to send to the IdP admin), confirm it worked, then
continue. The detailed IdP click-paths are in the module's
[README](../../../pre-built-assets/connect-idp-module/README.md) ("IdP Configuration Guide");
this skill gives the values and the order.

## 1. Gather the inputs

Ask (skip what the user already said):

1. **Environment**: the AWS profile, region and Connect instance, and the environment name
   (`dev`, `uat`, `prod`, ...). One stack and two IdP applications per environment.
2. **Prefix**: the project's `NamePrefix` (the root stack's parameter, e.g. `dfx5bank-connect-dev`;
   `aws cloudformation describe-stacks --stack-name <root-stack> --query "Stacks[0].Parameters"`).
   It must be the DFX5 delivery permission set's `PREFIX` (see Permissions). Without a root stack
   from this repo, use the `PREFIX` agreed with the client.
3. **IdP**: Microsoft Entra ID (Azure AD), Okta, AWS IAM Identity Center (when the client brokers
   their IdP through it), or another SAML 2.0 IdP.
4. **Who configures the IdP**: the user, or the client's IdP admin (then step 4 becomes a handoff).
5. **Username format**: what identifies a user in the IdP and in Connect (`RoleSessionName`),
   usually the email or UPN. Connect usernames must match it exactly.

Check the instance and what already exists:

```bash
# Must be SAML - an instance's identity management type can't be changed after creation
aws connect describe-instance --profile <p> --region <r> --instance-id <instance-id> \
  --query "Instance.[InstanceAlias,IdentityManagementType,Arn]" --output text

# Existing SAML providers and federation stacks - don't create a second set for the same environment
aws iam list-saml-providers --profile <p> --query "SAMLProviderList[].Arn" --output text
aws cloudformation list-stacks --profile <p> --region <r> \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?contains(StackName,'idp')].StackName" --output text
```

- `CONNECT_MANAGED` or `EXISTING_DIRECTORY`: SAML isn't possible on this instance. Tell the user
  it needs a new instance with SAML (this repo's `stacks/`), and stop.
- Providers named `<prefix>-identity-provider-*-<env>` already exist: ask whether this
  environment is already set up (then skip to the step that's missing) or the names should differ.

## 2. Deploy the federation stack

Stack name: `<prefix>-idp` (the prefix already names the environment). Create the change set
without executing it:

```bash
aws cloudformation deploy --profile <p> --region <r> \
  --template-file pre-built-assets/connect-idp-module/template_idp_integration.yaml \
  --stack-name <prefix>-idp \
  --parameter-overrides NamePrefix=<prefix> Environment=<env> ConnectInstanceArn=<instance-arn> \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-execute-changeset
```

Expected: 3 × `Add` (`IdentityProviderAdmin`, `IdentityProviderAgent`, `FederationRole`). Show the
change set and execute only after the user says go, then wait for `stack-create-complete` and
read the outputs:

```bash
aws cloudformation describe-stacks --profile <p> --region <r> --stack-name <prefix>-idp \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table
```

## 3. The values for the IdP

Every IdP needs two SAML applications per environment: **Management console** (admins,
supervisors) and **Agent workspace** (agents). They differ only in the relay state and the `Role`
claim. Build this table from the outputs and give it to the user:

| Setting | Management console app | Agent workspace app |
|---|---|---|
| ACS / Reply URL | `https://signin.aws.amazon.com/saml` | `https://signin.aws.amazon.com/saml` |
| Entity ID / Audience | `https://signin.aws.amazon.com/saml` (Entra ID: `...saml#1`) | same (Entra ID: `...saml#2`) |
| Relay state | `AmazonConnectManagementConsoleRelayState` | `AmazonConnectAgentWorkspaceRelayState` |
| Claim `https://aws.amazon.com/SAML/Attributes/Role` | `AdminSAMLRole` | `AgentSAMLRole` |
| Claim `https://aws.amazon.com/SAML/Attributes/RoleSessionName` | the username (email or UPN) | same |
| Claim `https://aws.amazon.com/SAML/Attributes/SessionDuration` | `900` | `900` |

Per IdP (details in the module README):

- **Entra ID**: two non-gallery Enterprise Applications. Entity IDs must differ, so append `#1`
  and `#2`. In **Attributes & Claims**, each of the three claims splits across two fields: put
  `https://aws.amazon.com/SAML/Attributes` in **Namespace** and just the short name (`Role`,
  `RoleSessionName`, `SessionDuration`) in **Name** - Entra joins them into the full claim URI.
  Putting the full URI in **Name** with **Namespace** left blank sends a different claim name and
  Connect won't see it. `RoleSessionName` from `user.userprincipalname` (or `user.mail` if Connect
  usernames are emails). Download each app's **Federation Metadata XML**.
- **Okta**: two SAML 2.0 app integrations, attribute statements as above (`RoleSessionName` =
  `user.email` or `user.login`), metadata from each app's **Sign On** tab.
- **IAM Identity Center**: the **Amazon Connect** catalog application, twice. Audience
  `urn:amazon:webservices`, ACS URL as above, and attribute mappings `Subject` = `${user:email}`
  (emailAddress), plus the three claims. Download the Identity Center SAML metadata.
- **Other SAML IdP**: the table above is all it needs. The `Role` value is the literal
  `<role-arn>,<provider-arn>` string.

If the client's IdP admin does this, offer to draft an email with the table, the two
applications to create, which users or groups to assign to each, and what to send back (each
application's metadata XML). Send nothing yourself.

## 4. Assign users in the IdP

The IdP admin assigns users or groups to each application: agents to the agent workspace app;
admins and supervisors to the management console app (and the agent workspace app if they also
take contacts). Agree on the groups with the user; they're often the same groups that later map to
security profiles.

## 5. Load the real metadata

When the metadata XML arrives (one file per application), save it outside the repo (it's
client-specific) and check it before loading:

```bash
# entityID and the signing certificate's expiry
python3 - <file>.xml <<'EOF'
import re, sys, subprocess, textwrap
x = open(sys.argv[1]).read()
print("entityID:", re.search(r'entityID="([^"]+)"', x).group(1))
for c in dict.fromkeys(re.findall(r"<(?:ds:)?X509Certificate>([^<]+)<", x)):
    pem = "-----BEGIN CERTIFICATE-----\n" + "\n".join(textwrap.wrap(c.strip(), 64)) + "\n-----END CERTIFICATE-----\n"
    print(subprocess.run(["openssl", "x509", "-noout", "-subject", "-enddate"], input=pem, capture_output=True, text=True).stdout.strip())
EOF
```

The entityID must be the client's IdP (not `bootstrap.placeholder`), and the certificate must not
expire soon - note the expiry date in the project documentation, because sign-in breaks the day it
expires unless the new metadata is loaded first.

Show the user which file goes to which provider, then update after they confirm:

```bash
aws iam update-saml-provider --profile <p> \
  --saml-provider-arn arn:aws:iam::<account-id>:saml-provider/<prefix>-identity-provider-admin-<env> \
  --saml-metadata-document file://<management-console-app>.xml

aws iam update-saml-provider --profile <p> \
  --saml-provider-arn arn:aws:iam::<account-id>:saml-provider/<prefix>-identity-provider-agent-<env> \
  --saml-metadata-document file://<agent-workspace-app>.xml
```

If both applications share one signing certificate (and the same entityID), one file can go to
both providers.

The metadata is set outside CloudFormation, so drift detection reports both providers as
modified. That's expected. Don't delete or replace the providers in the stack: that would bring
back the placeholder and break sign-in.

## 6. Create a test user in Connect

A federated user signs in only if a Connect user with the **same username** as their
`RoleSessionName` exists. Create one test user (no password with SAML), with the security and
routing profiles the user picks:

```bash
aws connect create-user --profile <p> --region <r> --instance-id <instance-id> \
  --username <exact RoleSessionName, e.g. jana.novak@client.com> \
  --identity-info FirstName=<first>,LastName=<last> \
  --phone-config PhoneType=SOFT_PHONE \
  --security-profile-ids <security-profile-id> --routing-profile-id <routing-profile-id>
```

No `Email` in `--identity-info`: a SAML instance rejects it ("Email is not required for this
directory type"); the username carries the identity. (`aws connect list-security-profiles` and
`list-routing-profiles` give the IDs.) For many users,
point the user to SCIM provisioning (below) rather than creating them by hand.

## 7. Test

1. The test user opens the IdP's portal (Entra **My Apps**, the Okta dashboard, the Identity
   Center access portal) and starts the **Management console** app. They should land in the
   Connect admin website.
2. Then the **Agent workspace** app. They should land in the agent workspace.

Sign-in starts from the IdP (IdP-initiated); the relay state decides where the user lands.

If it fails:

| Symptom | Usual cause |
|---|---|
| AWS sign-in page: "Your request included an invalid SAML response" | Metadata not loaded or for the wrong app, expired certificate, or a claim name misspelled |
| "Not authorized to perform sts:AssumeRoleWithSAML" | `Role` claim isn't exactly `<role-arn>,<provider-arn>` for this app's provider, or the IdP sends a different audience/recipient than `https://signin.aws.amazon.com/saml` |
| Lands in the AWS console instead of Connect | Relay state missing or wrong |
| Connect: user not found / access denied after federation | No Connect user with exactly the `RoleSessionName` username |
| Entra ID: "application with identifier ... was not found" or both apps open the same one | The two apps share an Entity ID - use `#1` and `#2` |

For SAML errors, a SAML tracer browser extension shows the assertion the IdP sends (claim names
and values) without needing access to the IdP.

## 8. Before go-live (tell the user)

- **Emergency access**: admins with AWS console access can still open the instance with
  **Log in for emergency access** in the Connect console. Keep that limited to a few people.
- **Certificate rotation**: the IdP's signing certificate expires (Entra ID default: 3 years).
  Plan to load the new metadata (step 5) before the expiry date.
- **User provisioning**: for more than a handful of users, use the module's
  `template_scim_integration.yaml` (Entra ID SCIM or Okta event hooks, see the module README)
  instead of creating users by hand.
- **One stack per environment**, each with its own two IdP applications - never point a
  production IdP application at a dev role.

## Permissions

The deploying identity needs `iam:CreateSAMLProvider`, `iam:UpdateSAMLProvider`,
`iam:TagSAMLProvider`, `iam:CreateRole`, `iam:PutRolePolicy`, `iam:GetRole` and
`connect:CreateUser`. The DFX5 delivery permission set (`permission-sets/delivery/`) covers
these, but scopes SAML providers and roles to `PREFIX-*`: use the permission set's prefix as
`NamePrefix`, or the stack fails with `AccessDenied`.

## Report back

Tell the user the stack name, the two provider ARNs and the federation role, the relay state URLs,
whether the real metadata is loaded (and the certificate expiry), the test user and the test
results, and what's still open (IdP assignments, more users or SCIM, documenting the certificate
expiry).
