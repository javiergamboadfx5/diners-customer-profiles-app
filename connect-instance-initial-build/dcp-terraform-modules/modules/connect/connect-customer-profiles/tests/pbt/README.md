# Property-test harness — `connect/connect-customer-profiles`

Feature: `connect-instance-initial-build`. This directory holds the
property-based testing (PBT) harness that the property tests (tasks 1.9, 1.10,
1.11, and the cross-module environment test 1.7) plug into. Task **1.5** sets up
only the harness, runner and shared generators, plus a smoke suite that proves
the harness runs. The individual properties are added by later tasks.

## Tooling choice

The design (`design.md` → *Testing Strategy → Property tests*) specifies:

- **Library:** [Hypothesis](https://hypothesis.readthedocs.io/) (Python), driven
  by `pytest`.
- **Settings:** each property runs with `max_examples >= 100`.
- **Tag comment:** every property test carries the comment
  `Feature: connect-instance-initial-build, Property <n>: <text>`.
- **Mechanism:** `validations.tf` and `naming.tf` are provider-free, so a
  fixture root under `tests/pbt/fixture/` links to those files, takes inputs
  from a generated `*.tfvars.json`, runs `terraform plan` with no providers, and
  exposes the computed `naming.tf` locals (domain name, KMS alias, domain ARN,
  SSM base, Name tags) as outputs. A rejected input is detected from the plan
  error.

## Data-source patch (profiles only)

The module's `naming.tf` builds `profiles_domain_arn` from three AWS data
sources (`aws_partition`, `aws_region`, `aws_caller_identity`) declared in
`main.tf`, which need the AWS provider and credentials at plan time. To stay
provider-free and offline, `harness.py` copies `naming.tf` and rewrites only
those three references to fixture stub variables (`var.stub_*` in
`fixture/stubs.tf`). The ARN then becomes a pure, deterministic function of its
inputs. **The committed module file is never modified** — only the throwaway
copy in the temp working directory. The real data-source wiring is covered by
the module's `terraform test` suite with a `mock_provider` (task 3.4).

## Layout

```
tests/pbt/
├── README.md                 # this file
├── pytest.ini                # Hypothesis profile (max_examples >= 100)
├── conftest.py               # shared pytest fixtures (the harness session)
├── harness.py                # terraform-plan runner + data-source patch
├── strategies.py             # shared Hypothesis generators / reference logic
├── test_smoke.py             # task 1.5 smoke suite (no real property yet)
└── fixture/
    ├── versions.tf           # relaxed required_version, NO providers
    ├── stubs.tf              # stub vars for the patched data-source refs
    └── outputs.tf            # exposes naming.tf locals
```

## Running

```bash
# from this directory
python -m pytest -q
```

Requirements: `terraform` on `PATH` and Python with `pytest` + `hypothesis`.

## Fallback (design note)

If Hypothesis cannot be provisioned on the Nexus-only runner, the fallback is
example-based tests using the same `harness.py` entry points; the gap is
recorded as a PR note.
