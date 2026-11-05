"""Terraform-plan harness for the provider-free property tests.

Feature: connect-instance-initial-build (task 1.5).

The harness exercises a module's provider-free logic (``naming.tf`` and
``validations.tf``) without AWS credentials. For a given set of inputs it:

1. Assembles a throwaway working directory that contains
   - a copy of the module's ``naming.tf`` and ``validations.tf``,
   - the fixture files under ``tests/pbt/fixture/`` (relaxed ``versions.tf`` with
     no providers, plus ``outputs.tf`` that re-exports the ``naming.tf`` locals),
   - the generated ``terraform.tfvars.json``.
2. Runs ``terraform plan`` with ``-backend=false`` and no provider plugins.
3. Returns a :class:`PlanResult`: ``accepted`` with the parsed outputs, or
   ``rejected`` with the captured error text.

``terraform init`` is run once per working directory. The directory is cached
per Python process and reused across Hypothesis examples, so each example only
pays for a ``plan`` (about a second).

The same API serves both Hypothesis tests and example-based fallback tests, so
only the test bodies differ between the two modes (see README).
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# tests/pbt/harness.py -> module root is three levels up.
PBT_DIR = Path(__file__).resolve().parent
FIXTURE_DIR = PBT_DIR / "fixture"
MODULE_ROOT = PBT_DIR.parent.parent

# Provider-free files copied from the module into every fixture working dir.
PROVIDER_FREE_FILES = ("naming.tf", "validations.tf", "variables.tf")

TERRAFORM_BIN = os.environ.get("TERRAFORM_BIN", "terraform")


@dataclass
class PlanResult:
    """Outcome of a single fixture plan."""

    accepted: bool
    outputs: dict[str, Any] = field(default_factory=dict)
    error: str = ""

    def output(self, name: str) -> Any:
        """Return the value of a named Terraform output."""
        return self.outputs[name]["value"]


class HarnessError(RuntimeError):
    """Raised when terraform fails for a reason other than input rejection."""


def _run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=str(cwd),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


class FixtureWorkspace:
    """A reusable terraform working directory built from the fixture.

    One instance owns one initialized temp directory. Call :meth:`plan` with a
    dict of inputs to evaluate the provider-free logic. The instance is cheap to
    reuse across many Hypothesis examples; call :meth:`close` (or use it as a
    context manager) to delete the temp directory.
    """

    def __init__(self) -> None:
        self._root = Path(tempfile.mkdtemp(prefix="pbt-connect-instance-"))
        self._initialized = False
        self._assemble()

    # -- setup --------------------------------------------------------------
    def _assemble(self) -> None:
        # Copy the module's provider-free logic.
        for name in PROVIDER_FREE_FILES:
            src = MODULE_ROOT / name
            if not src.exists():
                raise HarnessError(f"provider-free file not found: {src}")
            shutil.copy2(src, self._root / name)

        # Copy the fixture files (versions.tf, outputs.tf, any *.tf stub).
        for src in FIXTURE_DIR.glob("*.tf"):
            shutil.copy2(src, self._root / src.name)

    def _init(self) -> None:
        if self._initialized:
            return
        proc = _run(
            [TERRAFORM_BIN, "init", "-backend=false", "-input=false", "-no-color"],
            self._root,
        )
        if proc.returncode != 0:
            raise HarnessError(
                "terraform init failed:\n" + proc.stdout + "\n" + proc.stderr
            )
        self._initialized = True

    # -- use ----------------------------------------------------------------
    def plan(self, variables: dict[str, Any]) -> PlanResult:
        """Run the fixture with ``variables`` and return the outcome."""
        self._init()

        tfvars = self._root / "terraform.tfvars.json"
        tfvars.write_text(json.dumps(variables), encoding="utf-8")

        plan_file = self._root / "plan.tfplan"
        proc = _run(
            [
                TERRAFORM_BIN,
                "plan",
                "-input=false",
                "-no-color",
                "-lock=false",
                f"-out={plan_file.name}",
            ],
            self._root,
        )

        if proc.returncode != 0:
            # Plan failed: input rejected by a validation/check, or a genuine
            # harness error. Validation and check errors are the expected
            # "rejected" path; surface everything as the error text so the test
            # can assert on the message.
            return PlanResult(accepted=False, error=proc.stdout + "\n" + proc.stderr)

        outputs = self._read_outputs(plan_file)
        return PlanResult(accepted=True, outputs=outputs)

    def _read_outputs(self, plan_file: Path) -> dict[str, Any]:
        show = _run(
            [TERRAFORM_BIN, "show", "-json", "-no-color", plan_file.name],
            self._root,
        )
        if show.returncode != 0:
            raise HarnessError(
                "terraform show failed:\n" + show.stdout + "\n" + show.stderr
            )
        data = json.loads(show.stdout)
        # Planned outputs live under planned_values.outputs for a no-resource plan.
        planned = data.get("planned_values", {}).get("outputs")
        if planned:
            return planned
        return data.get("outputs", {})

    # -- lifecycle ----------------------------------------------------------
    def close(self) -> None:
        shutil.rmtree(self._root, ignore_errors=True)

    def __enter__(self) -> "FixtureWorkspace":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()


def smoke_check() -> PlanResult:
    """Build a fixture, run one valid plan and return the result.

    Used by the task 1.5 smoke suite to prove the harness is wired correctly.
    """
    with FixtureWorkspace() as ws:
        return ws.plan(
            {
                "component": "storage",
                "domain": "diners",
                "environment": "dev",
                "workload": "channels",
                "region_code": "use1",
                "org_id": "o-abcde12345",
                "account_id": "123456789012",
                "cde_scope": False,
            }
        )
