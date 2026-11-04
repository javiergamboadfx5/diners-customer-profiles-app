---
name: enable-customer-profiles
description: Enable Amazon Connect Customer Profiles on a Connect instance using this repo's stacks/modules/customer-profiles module - creates the Customer Profiles domain encrypted with the project's customer-managed KMS key (or a key passed in), connects it to the instance so contact records flow into it, updates the key policy automatically when the key was created by this repo, and tells the user exactly what to add when the key is external. Use when asked to enable, add or set up Customer Profiles, customer profiles domain, or customer history in the agent workspace on a Connect instance (also a prerequisite for Cases).
---

# Enable Customer Profiles on a Connect instance

Customer Profiles is an `AWS::CustomerProfiles::Domain` connected to the instance by an
`AWS::CustomerProfiles::Integration` whose URI is the instance ARN and whose object type is the
domain's `CTR` object type (`AWS::CustomerProfiles::ObjectType`), created from the built-in
`CTR-AutoAssociateOnly` template (console: **Profile creation and auto-association →
Auto-associate profiles only**). Contact records flow into the domain once a contact ends and are
associated with the profile that has the contact's `_ctrContactId` key (added during the contact,
for example by the flow's **Customer profiles** block or `AddProfileKey`), or else one with the
same `_phone`. **No profile is created from contact data, and email addresses are not matched** -
so for email, a contact is only linked when the flow (or the agent) links it. This keeps the domain
free of inferred duplicates. (The other templates are `CTR`, which always infers a profile, and
`CTR-NoInferred`, which infers one when nothing matches.) The module sets it the way the console
does - integration on object type `CTR`, object type from the template - so the console's **Edit**
stays available; pointing the integration at the template name directly works but makes the
console report "A custom CTR integration ... has been detected" and lock the setting. This repo creates both with
[`stack/modules/customer-profiles/customer-profiles.yaml`](stack/modules/customer-profiles/customer-profiles.yaml) (copied to the project's `stacks/modules/customer-profiles/`),
switched on by `EnableCustomerProfiles=true` in [`stacks/template.yaml`](../../../stacks/template.yaml).
The domain is named `amazon-connect-<prefix>` (the root stack's `NamePrefix`) - the literal
`amazon-connect-` is required: AWS's own `AmazonConnectServiceLinkedRolePolicy` hard-scopes the
Connect service-linked role's `profile:*` access to `domains/amazon-connect-*`, so the agent
workspace and Connect itself can only read a domain named this way, no matter what our own
delivery permission set allows. A domain named any other way deploys fine but then shows
"Please contact your administrator to review your Amazon Connect Role Policy" in the agent
workspace's Customer Profiles tab - found exactly this way during the delivery role test.
Stacks without `NamePrefix` keep the older `amazon-connect-<alias>` name.

Never create the domain through the console, with ad-hoc CLI calls, or with an AWS-owned key.
Always go through the module so the setup is repeatable across environments.

## 1. Identify the target

Confirm with the user: AWS profile, region and the instance (alias or ARN). Then check whether
the instance is already connected to a Customer Profiles domain - one integration per instance:

```bash
aws customer-profiles list-domains --profile <p> --region <r> --query "Items[].DomainName" --output text

# For each domain: is this instance's ARN an integration URI?
aws customer-profiles list-integrations --profile <p> --region <r> --domain-name <domain> \
  --query "Items[?Uri=='<instance-arn>'].[Uri,ObjectTypeName]" --output text
```

If the instance is already connected (for example enabled in the console), stop and ask whether
to keep that domain. The module can't adopt it; replacing it means deleting that integration
first, and the old domain's profiles stay in the old domain.

Find the stack that owns the instance, as in the `enable-ai-agents` skill (a root stack with an
`InstanceArn` output matching the instance).

- **Found:** step 2A.
- **Not found** (instance created outside this repo): step 2B.

## 2A. Instance deployed from this repo's `stacks/`

Check the stack parameter `KmsKeyArn`:

- **Blank:** `storage-layer` created the key. With `EnableCustomerProfiles=true` it adds the
  `AllowCustomerProfilesUseOfKey` (profile.amazonaws.com) statement itself; `connect.amazonaws.com`
  already has `kms:Decrypt` on this key through `AllowConnectServiceUseOfKey`, so nothing else is
  needed for the agent workspace to read profiles.
- **Set:** the key is external. The stack won't modify it. Go to step 4 after deploying.

**Add the module to the project first.** The accelerator's committed `stacks/` is a baseline
without it; this skill carries it in [`stack/`](stack/): the `customer-profiles` module, the root stack parameters, conditions, nested stack and outputs, the storage layer's `EnableCustomerProfiles` parameter and condition, and its two key policy statements. Apply it (it adds only what's missing, so re-running is safe):

```bash
scripts/utils/add-stack-module.py --bundle .claude/skills/enable-customer-profiles/stack --dry-run
scripts/utils/add-stack-module.py --bundle .claude/skills/enable-customer-profiles/stack
cfn-lint stacks/template.yaml stacks/modules/storage-layer/storage.yaml stacks/modules/customer-profiles/*.yaml
```

Review `git diff stacks/` with the user - the project's `stacks/` now owns these files.

Ask the user for the retention (`CustomerProfilesExpirationDays`, default 366 days, the console
default): profile data and contact history older than that are deleted. Use the client's data
retention policy if there is one.

The module always turns on the domain's **data store** (`DataStore.Enabled: true`), the
long-term store that Spark SQL segments (Advanced Segments) and predictive insights need. Tell
the user before deploying: it **can't be disabled** once enabled, and it keeps up to **10 years**
of profile data regardless of `CustomerProfilesExpirationDays` - in a client account, check that
against their data retention policy. It doesn't populate the agent workspace or calculated
attributes; storage and segment creation have no charge.

Before deploying, make sure the stack's current template matches the repo (the update redeploys
the whole root stack): compare the parsed `aws cloudformation get-template` output of the root
and nested stacks with the local files. Only the Customer Profiles parts should differ. Stop and
ask if anything else differs.

Package to the artifact bucket the stack already uses, then create a change set that sets
`EnableCustomerProfiles=true` (and `CustomerProfilesExpirationDays` if not the default), keeping
every other parameter with `UsePreviousValue=true`:

```bash
aws cloudformation package --profile <p> --region <r> \
  --template-file stacks/template.yaml --s3-bucket <artifact-bucket> \
  --output-template-file packaged-template.yaml

aws cloudformation create-change-set --profile <p> --region <r> \
  --stack-name <root-stack> --change-set-name enable-customer-profiles \
  --template-url <packaged template in S3> \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --include-nested-stacks \
  --parameters ParameterKey=EnableCustomerProfiles,ParameterValue=true \
               ParameterKey=<each other parameter>,UsePreviousValue=true
```

Review the change set, including the nested change sets, before executing. Expected:

| Resource | Action |
|---|---|
| `CustomerProfilesStack` | Add (nested: `CustomerProfilesDomain`, `ConnectInstanceIntegration`) |
| `StorageLayerStack` → `ConnectStorageKey` | Modify, key policy only (project key) |
| Storage configs, bucket, bucket policy | Modify, no replacement (re-evaluated references only), or no change |

Anything with `Replacement: True`, or any other change, means stop and ask. Show the user the
summary and get a go-ahead, then run `execute-change-set` and wait for `stack-update-complete`.

## 2B. Instance created outside this repo

Deploy the module on its own. It needs an existing customer-managed key, so ask the user which
key to use (usually the instance's storage key: `aws connect list-instance-storage-configs`
shows it). This key is always external, so go to step 4 afterwards.

```bash
aws cloudformation deploy --profile <p> --region <r> \
  --template-file .claude/skills/enable-customer-profiles/stack/modules/customer-profiles/customer-profiles.yaml \
  --stack-name <prefix>-customer-profiles \
  --parameter-overrides InstanceArn=<instance-arn> NamePrefix=<prefix> InstanceAlias=<alias> KmsKeyArn=<key-arn> \
  --no-execute-changeset
```

Show the change set (2 × `Add`) and execute only after the user says go.

## 3. Verify in AWS (not just the stack status)

```bash
# Encrypted with the expected key, retention as set, data store enabled
aws customer-profiles get-domain --profile <p> --region <r> --domain-name amazon-connect-<prefix> \
  --query "[DomainName,DefaultEncryptionKey,DefaultExpirationDays,DataStore]"

# Connected to the instance (URI = instance ARN, object type CTR)
aws customer-profiles list-integrations --profile <p> --region <r> --domain-name amazon-connect-<prefix>

# The CTR object type comes from the CTR-AutoAssociateOnly template
aws customer-profiles get-profile-object-type --profile <p> --region <r> \
  --domain-name amazon-connect-<prefix> --object-type-name CTR --query "[ObjectTypeName,TemplateId]"

# Project key: AllowCustomerProfilesUseOfKey is present
aws kms get-key-policy --profile <p> --region <r> --key-id <key-id> --query Policy --output text
```

In the Connect console the instance's **Customer profiles** page should show the domain.

## 4. External key: tell the user what to add

A key not created by this repo is never modified. Read its policy (`aws kms get-key-policy`). If
it doesn't already allow `profile.amazonaws.com` to use the key and `connect.amazonaws.com` to
decrypt, tell the user clearly that **Customer Profiles won't work until the key's owner adds
these statements**. The root stack returns them in its `CustomerProfilesKmsKeyPolicyAction`
output:

```json
[
  {
    "Sid": "AllowCustomerProfilesUseOfKey",
    "Effect": "Allow",
    "Principal": { "Service": "profile.amazonaws.com" },
    "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant"],
    "Resource": "*",
    "Condition": { "StringEquals": { "aws:SourceAccount": "<account-id>" } }
  },
  {
    "Sid": "AllowConnectDecryptForCustomerProfiles",
    "Effect": "Allow",
    "Principal": { "Service": "connect.amazonaws.com" },
    "Action": "kms:Decrypt",
    "Resource": "*",
    "Condition": { "StringEquals": { "aws:SourceAccount": "<account-id>" } }
  }
]
```

Only change the key policy yourself if the user explicitly asks you to and confirms they own the
key.

## 5. Agent access

A contact from someone without a profile shows no profile in the agent workspace (the
template never creates one): an agent with **Create** permission can create it from the contact.
Later **calls** from the same number are then associated automatically (`_phone`); **email**
contacts are only associated when the inbound flow links them (Customer profiles block: find the
profile by email address, then associate the contact).

Profiles only show up for users whose security profile allows them. Tell the user to grant, per
security profile (**Users → Security profiles → Customer Profiles**): **View** for agents, and
**Create** / **Edit** where agents should create or update profiles. This is a manual step (or
part of the project's security profile resources).

## Permissions and known issues

- The deploying identity needs `profile:CreateDomain`, `profile:PutIntegration`,
  `profile:TagResource`, `connect:DescribeInstance`, and `kms:CreateGrant` + `kms:DescribeKey`
  on the key. The DFX5 delivery permission set (`permission-sets/delivery/`) covers these.
- The domain name and encryption key can't be changed later without replacing the domain. It has
  `DeletionPolicy: Retain` (and `UpdateReplacePolicy: Retain`): `EnableCustomerProfiles=false`,
  deleting the stack or a replacement removes the association with the instance but keeps the
  domain and its profiles. Delete a retained domain yourself (`aws customer-profiles delete-domain`)
  only when its profiles are no longer needed; to enable Customer Profiles again on the same
  instance, import the retained domain into the stack instead of creating a new one.
- The data store is always enabled and can't be turned off; deleting its data means deleting
  profiles (`DeleteProfile`), object types or the domain. Domains created by an older copy of the
  module get it on their next root stack update (an in-place update, no replacement).
- The module doesn't turn on identity resolution (duplicate matching), add object types for
  external data, or connect other sources (S3, Salesforce, Zendesk). Those are project-specific.
- Cases needs Customer Profiles: use the `enable-cases` skill afterwards (or in the same change
  set).

## Report back

Tell the user the domain name, the instance it's connected to, which key encrypts it, the
retention and that the data store is on (up to 10 years, can't be disabled). Say whether the key policy was updated automatically (project key) or still needs
the statements from step 4 (external key), and remind them of the security profile permissions
(step 5).
