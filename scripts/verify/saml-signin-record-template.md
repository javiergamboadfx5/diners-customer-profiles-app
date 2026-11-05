# Manual sign-in record: Entra ID SAML federation (dev)

Requirements 14.3 and 14.4 of `connect-instance-initial-build`. Complete this record after the SAML_Stack apply. `verify-saml.sh` covers the AWS side (providers, role, policy, identity type). This record covers the sign-in test that no CLI call can prove.

Do not store passwords, MFA codes, session tokens or SAML assertions in this record. Screenshots must not show them either.

## Environment

| Field | Value |
|---|---|
| Environment | dev |
| Account | `<account ID from as-built record>` |
| Region | us-east-1 |
| Instance ID | `<from SSM connect-instance-id>` |
| Admin relay state URL | `<output admin_relay_state_url of SAML_Stack>` |
| Agent relay state URL | `<output agent_relay_state_url of SAML_Stack>` |
| Entra ID session claim | `SessionDuration = 900` for both enterprise apps |
| Connect username rule | Connect username equals the UPN of the test user |

## Test cases

Run each case from a clean browser session. Start the flow from the Entra ID "My Apps" portal (IdP-initiated sign-in), not from the Connect URL.

| Case | Test | URL used | UPN | Expected result |
|---|---|---|---|---|
| S-1 | IdP-initiated sign-in to the management console, test user assigned to the admin app | Admin relay state URL (`destination=%2Fconnect`) | `<test user UPN>` | Lands in the Connect management console (`/connect`) |
| S-2 | IdP-initiated sign-in to the agent workspace, test user assigned to the agent app | Agent relay state URL (`destination=%2Fagent-app-v2`) | `<test user UPN>` | Lands in the agent workspace (`/agent-app-v2`) |
| S-3 | Refused sign-in, user without Entra ID assignment to either app | Admin or agent relay state URL | `<unassigned user UPN>` | Entra ID refuses the sign-in. No Connect session is created |

## Record per run

Copy this block once for each case (S-1, S-2, S-3).

```
Case:              S-<n>
Date (UTC):        YYYY-MM-DDTHH:MM:SSZ
Tester:            <name, role>
UPN:               <user principal name used>
URL:               <full URL used, without tokens>
Result:            pass | fail
Observed:          <one line: page reached, or error shown>
Screenshot ref:    <evidence store path or ticket attachment ID>
Approver:          <name, role, date>
```

| Field | Rule |
|---|---|
| Date | UTC timestamp of the attempt. |
| Tester | The person who ran the test. |
| UPN | Must match the Connect username shown after sign-in (S-1 and S-2). |
| URL | The relay state URL used. Remove any session or token parameter. |
| Result | `pass` only when the expected result in the case table is observed. Any other outcome is `fail`. |
| Screenshot reference | Pointer to the stored screenshot. Do not paste the image into the record. |
| Approver | Person who reviews the record. Use a different person from the tester. |

## Outcome rules

- A `fail` on any case (S-1, S-2 or S-3) keeps the dev environment out of the as-built report (Requirement 14.4). Record the defect and retest after the fix.
- S-3 passes only when the refusal comes from Entra ID or from the app assignment. A Connect session that opens for the unassigned user is a `fail`.
- If `cde_scope` is `true`, attach the Ciberseguridad decision on the 12 h Connect session against the L14 IA-3 idle limit (Requirement 10.10). Reference that decision in the Approver row.
- Record the certificate expiry date of each signing certificate in the certificate inventory when real metadata is loaded (Requirement 10.9). This is not part of the sign-in test.

## Summary

| Case | Date (UTC) | Tester | UPN | Result | Screenshot ref | Approver |
|---|---|---|---|---|---|---|
| S-1 | | | | | | |
| S-2 | | | | | | |
| S-3 | | | | | | |
