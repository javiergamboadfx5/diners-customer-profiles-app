---
name: deploy-connect-instance
description: Deploy a new Amazon Connect instance from this repo's baseline stacks/ (root stack with the instance, the storage-layer nested stack with the S3 bucket and customer-managed KMS key, and the call recording and chat transcript storage configs) - agrees the values that can't be changed later with the user first (instance alias, identity management type, stack name per client and environment, KMS key), prepares the artifact bucket, shows the change set and deploys only after approval, verifies the instance and points to the next skills (SAML, sample flows, features). Use when asked to deploy, create, spin up or stand up a new Connect instance or environment (dev, UAT, prod) with this accelerator.
---

# Deploy a new Connect instance

The baseline root stack ([`stacks/template.yaml`](../../../stacks/template.yaml), background in
[`stacks/README.md`](../../../stacks/README.md)) creates:

- `AWS::Connect::Instance` - alias, identity management type, inbound/outbound calls, flow logs.
- `StorageLayerStack` ([`modules/storage-layer/storage.yaml`](../../../stacks/modules/storage-layer/storage.yaml)):
  a customer-managed KMS key (unless `KmsKeyArn` is passed, alias `alias/<NamePrefix>-connect-storage`)
  and one storage bucket, `<NamePrefix>-<account-id>-connect-storage`, with its bucket policy and
  CORS rule. (Without `NamePrefix`, the older names: `<account-id>-<alias>-connect-storage` and
  `alias/connect/<alias>-storage`.)
- `CallRecordingsStorageConfig` and `ChatTranscriptsStorageConfig`: prefixes
  `connect/call-recordings` and `connect/chat-transcripts` in that bucket, encrypted with the key.

**Two values can never be changed** without deleting and recreating the instance (with all its
flows, users, numbers and history): the **alias** and the **identity management type**. So this
skill never picks them itself. Agree every value with the user, show the change set, and deploy
only after they approve.

## 1. Agree the values

Ask (skip what the user already said), and give a recommendation for each:

1. **AWS profile and region.** Check the profile works (`aws sts get-caller-identity`) and that
   the account is the intended one (name, ID). In a client account, confirm the region is the one
   in the design (data residency).
2. **Client and environment**, e.g. `dfx5bank` and `dev` (`uat`, `prod`). One instance per
   environment.
3. **Prefix (derived, show it - don't ask for it separately)**: `<client>-connect-<env>`, e.g.
   `dfx5bank-connect-dev`. It is the stack name **and** `NamePrefix`, and it must be exactly the
   `PREFIX` of the DFX5 delivery permission set agreed with the client
   ([`permission-sets/delivery/`](../../../permission-sets/delivery/)): that set only allows writes
   to `PREFIX-*` stacks, buckets, key aliases, roles and functions, so anything else (just the
   client name, for example) fails with `AccessDenied` in the client's account. If the client
   agreed a different `PREFIX`, use that instead. Lowercase, up to 34 characters, and it can't be
   changed later without replacing the storage bucket and key. Every later skill finds the
   instance through this stack.
4. **Instance alias** (`InstanceAlias`, independent of the prefix - nothing derives it):
   becomes `https://<alias>.my.connect.aws/` and the native email domain
   `<alias>.email.connect.aws`. Globally
   unique across all accounts and regions, 1-62 letters, digits and hyphens, no leading or
   trailing hyphen. Suggest `<client>-<env>` (e.g. `dfx5bank-dev`); customers can see it in the
   email domain, so it should look right to them.
5. **Identity management type** (`IdentityManagementType`, no default on purpose):

   | Value | Recommend for |
   |---|---|
   | `SAML` | Client environments (the DFX5 default). Sign-in through the client's IdP, set up next with the `enable-saml-integration` skill. Until then, only emergency access from the AWS console works. |
   | `CONNECT_MANAGED` | Demos, PoCs and short-lived test instances: users and passwords created in Connect. Can't move to SAML later. |
   | `EXISTING_DIRECTORY` | The client's AWS Directory Service directory - ask for `DirectoryId` (`d-xxxxxxxxxx`) and check it with `aws ds describe-directories`. |

6. **KMS key** (`KmsKeyArn`): blank (recommended) creates a dedicated customer-managed key with a
   key policy scoped to the instance; the feature skills then update that policy themselves. An
   existing key (the client's) is never modified, so each feature skill will hand the key's owner
   a statement to add. Never AWS-owned keys or SSE-S3.
7. **Telephony and logs**: `EnableInboundCalls`, `EnableOutboundCalls`, `EnableContactflowLogs`
   (all `true` by default - keep them unless the design says otherwise).

**Production check.** If the environment is production (or the account or profile name says
prod/live), say so, and get an explicit yes on the alias and identity type before step 3.

Show the user the values as a table and wait for confirmation.

## 2. Pre-checks

```bash
# Instances already in the region - Connect allows 2 per account per region by default
aws connect list-instances --profile <p> --region <r> \
  --query "InstanceSummaryList[].[InstanceAlias,IdentityManagementType,InstanceStatus]" --output table

# The stack name must be free
aws cloudformation describe-stacks --profile <p> --region <r> --stack-name <stack> \
  --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "stack free"

# A retained bucket from an earlier attempt with the same prefix blocks the create
aws s3api head-bucket --profile <p> --bucket <prefix>-<account-id>-connect-storage >/dev/null 2>&1 \
  && echo "storage bucket EXISTS" || echo "storage bucket free"

# The artifact bucket (step 3)
aws s3api head-bucket --profile <p> --bucket cf-templates-<account-id>-<region> >/dev/null 2>&1 \
  && echo "artifact bucket exists" || echo "artifact bucket missing"
```

- An instance with the same alias in this account: stop, it's already deployed (find its stack
  by the `InstanceArn` output).
- At the instance quota: ask the user whether to delete an old instance or request a quota
  increase (**Service Quotas → Amazon Connect → Amazon Connect instances**).
- The stack exists in `ROLLBACK_COMPLETE`: an earlier create failed. Read its events
  (step 5), then delete it with the user's approval before retrying.
- The storage bucket already exists: it's from an earlier instance with this prefix (the bucket
  is retained on delete). If it's empty and the user agrees, delete it; if it holds recordings, stop
  and ask - choose another alias or keep the data.

An alias taken in another account only shows up when the stack fails (step 4).

## 3. Lint, package and create the change set

The root stack nests `storage-layer`, so it must be packaged to S3. Use the account's artifact
bucket `cf-templates-<account-id>-<region>` (the delivery permission set allows `cf-templates-*`,
the pattern of CloudFormation's own console bucket). If it doesn't exist, ask before creating it
(it holds only packaged templates):

```bash
aws s3api create-bucket --profile <p> --region <r> --bucket cf-templates-<account-id>-<region> \
  --create-bucket-configuration LocationConstraint=<r>     # omit this line in us-east-1
aws s3api put-public-access-block --profile <p> --bucket cf-templates-<account-id>-<region> \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Then lint, package and create the change set **without executing it**. Put the packaged template
in the scratchpad, not the repo:

```bash
cfn-lint stacks/template.yaml stacks/modules/storage-layer/storage.yaml

aws cloudformation package --profile <p> --region <r> \
  --template-file stacks/template.yaml --s3-bucket cf-templates-<account-id>-<region> \
  --s3-prefix <stack> --output-template-file <scratchpad>/packaged-template.yaml

aws cloudformation deploy --profile <p> --region <r> \
  --stack-name <stack> --template-file <scratchpad>/packaged-template.yaml \
  --parameter-overrides InstanceAlias=<alias> NamePrefix=<prefix> IdentityManagementType=<type> \
    [DirectoryId=<d-...>] [KmsKeyArn=<arn>] \
  --capabilities CAPABILITY_IAM \
  --tags Client=<client> Environment=<env> \
  --no-execute-changeset
```

`cfn-lint`'s `W3002` (package needed) and `W1030` on `DirectoryId` are both expected and
suppressed repo-wide by [`.cfnlintrc.yaml`](../../../.cfnlintrc.yaml).

Show the change set (`aws cloudformation describe-change-set --change-set-name <arn from the
output>`). Expected, all `Add`:

| Resource | Type |
|---|---|
| `ConnectInstance` | `AWS::Connect::Instance` |
| `StorageLayerStack` | `AWS::CloudFormation::Stack` (nested: key and alias unless `KmsKeyArn`, bucket, bucket policy) |
| `CallRecordingsStorageConfig`, `ChatTranscriptsStorageConfig` | `AWS::Connect::InstanceStorageConfig` |

Repeat the alias and identity type next to the change set, and execute only after the user says
go. A project's `stacks/` may already have feature modules added by other skills; then the change
set has more rows - explain each one, or ask the user to deploy the baseline first.

## 4. Deploy

```bash
aws cloudformation execute-change-set --profile <p> --region <r> --change-set-name <change-set-arn>
aws cloudformation wait stack-create-complete --profile <p> --region <r> --stack-name <stack>
```

Creating the instance takes a few minutes.

## 5. If it fails

```bash
aws cloudformation describe-stack-events --profile <p> --region <r> --stack-name <stack> \
  --query "StackEvents[?contains(ResourceStatus,'FAILED')].[LogicalResourceId,ResourceStatusReason]" --output text
```

- **Alias already in use** (another account or region has it): choose another alias with the user.
- **Instance quota reached**: see step 2.
- **Bucket already exists**: see step 2.
- **`AccessDenied`**: compare with the DFX5 delivery permission set (`permission-sets/delivery/`).
  `cloudformation:CreateChangeSet` denied on `stack/<prefix>/*` means the client's copy of the
  core policy predates the `arn:aws:cloudformation:*:ACCOUNT_ID:stack/PREFIX/*` entry (older
  copies only had `stack/PREFIX-*`, which doesn't match a stack named exactly the prefix): ask
  the client to add it to `CloudFormationScopedToPrefix`. A denial on a bucket, key alias or
  role usually means `NamePrefix` isn't the permission set's `PREFIX`.

A failed create leaves the stack in `ROLLBACK_COMPLETE`, and the storage bucket stays (it's
retained). Fix the cause, delete the stack (and the empty bucket) with the user's approval, then
go back to step 3.

## 6. Verify

```bash
aws cloudformation describe-stacks --profile <p> --region <r> --stack-name <stack> \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table

aws connect describe-instance --profile <p> --region <r> --instance-id <InstanceId output> \
  --query "Instance.[InstanceAlias,InstanceStatus,IdentityManagementType]" --output text   # ACTIVE

for t in CALL_RECORDINGS CHAT_TRANSCRIPTS; do
  aws connect list-instance-storage-configs --profile <p> --region <r> --instance-id <InstanceId output> \
    --resource-type $t --query "StorageConfigs[].S3Config.[BucketPrefix,EncryptionConfig.KeyId]" --output text
done
```

Both storage configs should point at the bucket with their prefix and the stack's KMS key.

## 7. Record it and hand over

Nothing in `stacks/` changes with a deployment - don't commit anything for it. In a **client
fork**, record the stack name, account, region, alias, identity type, instance ID and ARN, access
URL, bucket and key in the project's as-built documentation (`docs/02_execution/`). In the
**accelerator repo itself** (remote `dfx5/cx-project-accelerator`, e.g. a sandbox or test
deployment), leave the `docs/` templates blank - they're the starting point for every fork - and
only report the values.

Then tell the user how to sign in and what comes next:

- **SAML**: nobody can sign in yet. Run `enable-saml-integration`. Admins can meanwhile use
  **Log in for emergency access** on the instance in the Connect console.
- **CONNECT_MANAGED**: the first admin signs in with **Log in for emergency access** in the
  Connect console and creates users (or create an admin user with `aws connect create-user ...
  --password`, with the user's approval, and have them change the password on first sign-in).
- **EXISTING_DIRECTORY**: users come from the directory; create the Connect users with the
  directory usernames.
- `clear-sample-contact-flows` removes the demo flows every new instance gets.
- Features, each through its skill: `enable-email-channel`, `enable-ai-agents`,
  `add-knowledge-base`, `enable-contact-lens`, `enable-customer-profiles`, `enable-cases`,
  `enable-outbound-campaigns`, `enable-whatsapp-number`. Service availability differs by region
  (for example outbound campaigns, WhatsApp, and Bedrock models used by the email classifier);
  each skill checks its own.

## Delete an instance

Only when the user asks, and never in production without explicit confirmation of the stack
name: deleting the stack deletes the instance with everything in it (flows, users, numbers -
claimed phone numbers are released). The storage bucket and its data are retained; the KMS key the
stack created is scheduled for deletion (30 days), after which data encrypted with it can't be read. If the
bucket holds data to keep, cancel the key deletion (`aws kms cancel-key-deletion`) or copy the
data first. If `enable-email-channel` was applied, deleting an email address also calls
`ses:DeleteReceiptRule` on the deleting identity's behalf - see that skill's known issues.

## Report back

Tell the user the stack name, instance ID and ARN, access URL, identity type, bucket and key, and
the next step for sign-in (step 7).
