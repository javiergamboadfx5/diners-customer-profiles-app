"""Smoke suite for the PBT harness — connect/connect-instance.

Feature: connect-instance-initial-build (task 1.5).

These are NOT the feature's correctness properties (those arrive in tasks
1.6-1.12). They only prove the harness is wired correctly: the fixture builds,
`terraform init`/`plan` run with no providers, a valid input is accepted and
its naming outputs are returned, an invalid input is rejected with an error,
and the Hypothesis plumbing (ci profile, shared strategies) executes.
"""

from __future__ import annotations

from hypothesis import given, settings
from hypothesis import strategies as st

import strategies as strat
from harness import FixtureWorkspace, smoke_check

VALID_BASE = {
    "component": "storage",
    "domain": "diners",
    "environment": "dev",
    "workload": "channels",
    "region_code": "use1",
    "org_id": "o-abcde12345",
    "account_id": "123456789012",
    "cde_scope": False,
}


def test_harness_accepts_valid_input(workspace: FixtureWorkspace) -> None:
    result = workspace.plan(VALID_BASE)
    assert result.accepted, result.error
    name = result.output("bucket_name")
    assert name.startswith("dcp-diners-dev-channels-s3-connect-storage-use1-")
    assert len(name) <= 63
    assert result.output("bucket_name_ok") is True
    assert result.output("kms_alias_storage") == (
        "alias/dcp/diners/dev/channels/connect-storage"
    )


def test_harness_rejects_invalid_environment(workspace: FixtureWorkspace) -> None:
    result = workspace.plan({**VALID_BASE, "environment": "prd"})
    assert not result.accepted
    assert "environment" in result.error


def test_bucket_name_is_deterministic(workspace: FixtureWorkspace) -> None:
    first = workspace.plan(VALID_BASE)
    second = workspace.plan(VALID_BASE)
    assert first.accepted and second.accepted
    assert first.output("bucket_name") == second.output("bucket_name")


def test_smoke_check_helper() -> None:
    # Builds its own throwaway workspace end to end.
    result = smoke_check()
    assert result.accepted, result.error


@settings(max_examples=25)
@given(st.sampled_from(strat.REGION_CODES))
def test_hypothesis_plumbing_runs(region_code: str) -> None:
    # Trivial property over a shared strategy: the harness plans cleanly for
    # every approved region code. Proves generators + ci profile execute.
    with FixtureWorkspace() as ws:
        result = ws.plan({**VALID_BASE, "region_code": region_code})
        assert result.accepted, result.error
        assert f"-{region_code}-" in result.output("bucket_name")
