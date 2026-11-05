# Property-test harness — `connect/connect-saml-federation`

Feature: `connect-instance-initial-build`. This directory holds the
property-based testing (PBT) harness that the property tests (tasks 4.2, 4.3,
and the cross-module environment test 1.7) plug into. Task **1.5** sets up only
the harness, runner and shared generators, plus a smoke suite that proves the
harness runs. The individual properties are added by later tasks.

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
  exposes the computed `naming.tf` locals (role/policy names, SAML provider
  names, relay state URLs, length checks) as outputs. A rejected input is
  detected from the plan error.

## Layout

```
tests/pbt/
├── README.md                 # this file
├── pytest.ini                # Hypothesis profile (max_examples >= 100)
├── conftest.py               # shared pytest fixtures (the harness session)
├── harness.py                # terraform-plan runner over the fixture
├── strategies.py             # shared Hypothesis generators / reference logic
├── test_smoke.py             # task 1.5 smoke suite (no real property yet)
└── fixture/
    ├── versions.tf           # relaxed required_version, NO providers
    └── outputs.tf            # exposes naming.tf locals
```

At run time the harness builds a throwaway working directory with the fixture
files plus a copy of the module's `naming.tf`, `validations.tf` and
`variables.tf`. Copying keeps the harness portable (Windows, Linux, CodeBuild).

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
