"""Smoke suite for the PBT harness — connect/connect-customer-profiles.

Feature: connect-instance-initial-build (task 1.5).

These are NOT the feature's correctness properties (those arrive in tasks 1.9,
1.10, 1.11). They only prove the harness is wired correctly: the fixture builds,
the naming.tf data-source references are patched to the fixture stubs,
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
    "component": "domain",
    "domain": "diners",
    "environment": "dev",
    "workload": "channels",
    "region_code": "use1",
    "cde_scope": False,
    "default_expiration_days": 366,
}


def test_harness_accepts_valid_input(workspace: FixtureWorkspace) -> None:
    result = workspace.plan(VALID_BASE)
    assert result.accepted, result.error
    assert result.output("profiles_domain") == "amazon-connect-dcp-diners-dev-channels"
    assert result.output("kms_alias_profiles") == (
        "alias/dcp/diners/dev/channels/customer-profiles"
    )


def test_patched_domain_arn_is_pure(workspace: FixtureWorkspace) -> None:
    # After the data-source patch, the ARN is built from the stub defaults.
    result = workspace.plan(VALID_BASE)
    assert result.accepted, result.error
    assert result.output("profiles_domain_arn") == (
        "arn:aws:profile:us-east-1:123456789012:domains/"
        "amazon-connect-dcp-diners-dev-channels"
    )


def test_harness_rejects_expiration_out_of_range(workspace: FixtureWorkspace) -> None:
    result = workspace.plan({**VALID_BASE, "default_expiration_days": 1099})
    assert not result.accepted
    assert "default_expiration_days" in result.error


def test_harness_rejects_data_store_without_approval(workspace: FixtureWorkspace) -> None:
    result = workspace.plan({**VALID_BASE, "enable_data_store": True})
    assert not result.accepted
    assert "data_store_approval_ref" in result.error


def test_harness_rejects_invalid_environment(workspace: FixtureWorkspace) -> None:
    result = workspace.plan({**VALID_BASE, "environment": "prd"})
    assert not result.accepted
    assert "environment" in result.error


def test_smoke_check_helper() -> None:
    result = smoke_check()
    assert result.accepted, result.error


@settings(max_examples=25)
@given(st.sampled_from(strat.ENVIRONMENTS))
def test_hypothesis_plumbing_runs(environment: str) -> None:
    with FixtureWorkspace() as ws:
        result = ws.plan({**VALID_BASE, "environment": environment})
        assert result.accepted, result.error
        assert result.output("profiles_domain") == strat.expected_domain(
            environment, "channels"
        )
