"""Terraform-plan harness for the provider-free property tests.

Feature: connect-instance-initial-build (task 1.5).

The harness exercises the module's provider-free logic (``naming.tf`` and
``validations.tf``) without AWS credentials. For a given set of inputs it:

1. Assembles a throwaway working directory that contains
   - a copy of the module's ``validations.tf`` and ``variables.tf``,
   - a *patched* copy of ``naming.tf`` (see :func:`_patch_naming`),
   - the fixture files under ``tests/pbt/fixture/`` (relaxed ``versions.tf`` with
     no providers, ``stubs.tf`` with the data-source stand-ins, and
     ``outputs.tf`` that re-exports the ``naming.tf`` locals),
   - the generated ``terraform.tfvars.json``.
2. Runs ``terraform plan`` with ``-backend=false`` and no provider plugins.
3. Returns a :class:`PlanResult`: ``accepted`` with the parsed outputs, or
   ``rejected`` with the captured error text.

Why patch ``naming.tf``?
    The module's ``profiles_domain_arn`` local reads three AWS data sources
    (``aws_partition``, ``aws_region``, ``aws_caller_identity``) declared in the
    module's ``main.tf``. Those need the AWS provider and credentials at plan
    time, which would break the provider-free, offline contract of the harness.
    The harness rewrites only those three references to the fixture stub
    variables (``var.stub_*``), turning the ARN into a pure function of its
    inputs. The committed module file is never touched; only the throwaway copy
    is rewritten. The real data-source wiring is covered by the module's
    ``terraform test`` suite (task 3.4).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

PBT_DIR = Path(__file__).resolve().parent
FIXTURE_DIR = PBT_DIR / "fixture"
MODULE_ROOT = PBT_DIR.parent.parent

# Files copied verbatim from the module into the fixture working dir.
VERBATIM_FILES = ("validations.tf", "variables.tf")
# naming.tf is copied with the data-source patch applied.
PATCHED_FILE = "naming.tf"

# Data-source references rewritten to fixture stub variables so the harness
# stays provider-free. Order does not matter; each is a plain substring swap.
DATA_SOURCE_PATCHES = {
    "data.aws_partition.current.partition": "var.stub_partition",
    "data.aws_region.current.name": "var.stub_region",
    "data.aws_caller_identity.current.account_id": "var.stub_account_id",
}

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


def _patch_naming(text: str) -> str:
    """Rewrite the three AWS data-source references to fixture stub variables."""
    for needle, replacement in DATA_SOURCE_PATCHES.items():
        text = text.replace(needle, replacement)
    # Guard: no un-patched aws data-source reference may remain, or the plan
    # would fail with "Reference to undeclared resource".
    leftover = re.search(r"data\.aws_[a-z_]+\.", text)
    if leftover:
        raise HarnessError(
            "naming.tf still references an un-stubbed AWS data source: "
            f"{leftover.group(0)}; extend DATA_SOURCE_PATCHES."
        )
    return text


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
        self._root = Path(tempfile.mkdtemp(prefix="pbt-connect-profiles-"))
        self._initialized = False
        self._assemble()

    def _assemble(self) -> None:
        for name in VERBATIM_FILES:
            src = MODULE_ROOT / name
            if not src.exists():
                raise HarnessError(f"provider-free file not found: {src}")
            shutil.copy2(src, self._root / name)

        naming_src = MODULE_ROOT / PATCHED_FILE
        if not naming_src.exists():
            raise HarnessError(f"provider-free file not found: {naming_src}")
        patched = _patch_naming(naming_src.read_text(encoding="utf-8"))
        (self._root / PATCHED_FILE).write_text(patched, encoding="utf-8")

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
                "component": "domain",
                "domain": "diners",
                "environment": "dev",
                "workload": "channels",
                "region_code": "use1",
                "cde_scope": False,
                "default_expiration_days": 366,
            }
        )
