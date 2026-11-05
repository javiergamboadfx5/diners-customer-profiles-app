"""Terraform-plan harness for the provider-free property tests.

Feature: connect-instance-initial-build (task 1.5).

The harness exercises the module's provider-free logic (``naming.tf`` and
``validations.tf``) without AWS credentials. For a given set of inputs it:

1. Assembles a throwaway working directory that contains
   - a copy of the module's ``naming.tf``, ``validations.tf`` and ``variables.tf``,
   - the fixture files under ``tests/pbt/fixture/`` (relaxed ``versions.tf`` with
     no providers, plus ``outputs.tf`` that re-exports the ``naming.tf`` locals),
   - the generated ``terraform.tfvars.json``.
2. Runs ``terraform plan`` with ``-backend=false`` and no provider plugins.
3. Returns a :class:`PlanResult`: ``accepted`` with the parsed outputs, or
   ``rejected`` with the captured error text.

``terraform init`` is run once per working directory and reused across
Hypothesis examples, so each example only pays for a ``plan``.
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

PBT_DIR = Path(__file__).resolve().parent
FIXTURE_DIR = PBT_DIR / "fixture"
MODULE_ROOT = PBT_DIR.parent.parent

PROVIDER_FREE_FILES = ("naming.tf", "validations.tf", "variables.tf")

TERRAFORM_BIN = os.environ.get("TERRAFORM_BIN", "terraform")


@dataclass
class PlanResult:
    """Outcome of a single fixture plan."""

    accepted: bool
    outputs: dict[str, Any] = field(default_factory=dict)
    error: str = ""

    def output(self, name: str) -> Any:
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
    """A reusable, initialized terraform working directory built from the fixture."""

    def __init__(self) -> None:
        self._root = Path(tempfile.mkdtemp(prefix="pbt-connect-saml-"))
        self._initialized = False
        self._assemble()

    def _assemble(self) -> None:
        for name in PROVIDER_FREE_FILES:
            src = MODULE_ROOT / name
            if not src.exists():
                raise HarnessError(f"provider-free file not found: {src}")
            shutil.copy2(src, self._root / name)
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

    def plan(self, variables: dict[str, Any]) -> PlanResult:
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
            return PlanResult(accepted=False, error=proc.stdout + "\n" + proc.stderr)

        return PlanResult(accepted=True, outputs=self._read_outputs(plan_file))

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
        planned = data.get("planned_values", {}).get("outputs")
        if planned:
            return planned
        return data.get("outputs", {})

    def close(self) -> None:
        shutil.rmtree(self._root, ignore_errors=True)

    def __enter__(self) -> "FixtureWorkspace":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()


def smoke_check() -> PlanResult:
    """Build a fixture, run one valid plan and return the result."""
    with FixtureWorkspace() as ws:
        return ws.plan(
            {
                "domain": "diners",
                "environment": "dev",
                "workload": "channels",
                "region_code": "use1",
                "saml_resource_code": "saml",
                "max_session_duration": 3600,
                "instance_arn": (
                    "arn:aws:connect:us-east-1:123456789012:instance/"
                    "11111111-2222-3333-4444-555555555555"
                ),
            }
        )
