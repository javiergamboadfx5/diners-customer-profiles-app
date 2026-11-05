# Property-test harness — `connect/connect-instance`

Feature: `connect-instance-initial-build`. This directory holds the
property-based testing (PBT) harness that the property tests (tasks 1.6–1.12)
plug into. Task **1.5** sets up only the harness, runner and shared generators,
plus a smoke suite that proves the harness runs. The individual properties are
added by later tasks.

## Tooling choice

The design (`design.md` → *Testing Strategy → Property tests*) specifies:

- **Library:** [Hypothesis](https://hypothesis.readthedocs.io/) (Python), driven
  by `pytest`.
- **Settings:** each property runs with `max_examples >= 100`.
- **Tag comment:** every property test carries the comment
  `Feature: connect-instance-initial-build, Property <n>: <text>`.
- **Mechanism:** `validations.tf` and `naming.tf` are provider-free, so a
  fixture root under `tests/pbt/fixture/` links to those two files, takes inputs
  from a generated `*.tfvars.json`, runs `terraform plan` with no providers
  (about one second), and exposes the computed `naming.tf` locals as outputs.
  A rejected input is detected from the plan error; an accepted input yields the
  output values, which the Python reference predicate then checks.

This matches the design exactly. No AWS credentials are needed because the
fixture never declares a provider or an AWS resource.

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
    ├── variables.fixture.tf  # fixture-only input plumbing
    └── outputs.tf            # exposes naming.tf locals + validation result
```

At run time the harness builds a throwaway working directory that contains the
fixture files **plus a copy of the module's `naming.tf` and `validations.tf`**.
Copying (instead of a symlink) keeps the harness portable across Windows, Linux
and the CodeBuild runner. The copy is deterministic: the harness always reads
the current module files, so the tests exercise the real logic.

## Running

```bash
# from this directory
python -m pytest -q
```

Requirements: `terraform` on `PATH` and Python with `pytest` + `hypothesis`.
`terraform init` runs once per session with `-backend=false` and no provider
plugins to download (the fixture declares none).

## Fallback (design note)

If Hypothesis cannot be provisioned on the Nexus-only runner, the fallback is
example-based tests using the same `harness.py` entry points; the gap is
recorded as a PR note. The harness API (`plan_fixture`) is identical in both
modes, so only the test bodies change.
