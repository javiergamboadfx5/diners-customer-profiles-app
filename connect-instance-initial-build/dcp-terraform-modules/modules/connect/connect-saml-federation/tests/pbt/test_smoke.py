"""Smoke suite for the PBT harness — connect/connect-saml-federation.

Feature: connect-instance-initial-build (task 1.5).

These are NOT the feature's correctness properties (those arrive in tasks 4.2,
4.3). They only prove the harness is wired correctly: the fixture builds,
`terraform init`/`plan` run with no providers, a valid input is accepted and
its naming outputs are returned, an invalid input is rejected with an error,
and the Hypothesis plumbing (ci profile, shared strategies) executes.
"""

from __future__ import annotations

from hypothesis import given, settings
from hypothesis import strategies as st

import strategies as strat
from harness import FixtureWorkspace, smoke_check

VALID_ARN = (
    "arn:aws:connect:us-east-1:123456789012:instance/"
    "11111111-2222-3333-4444-555555555555"
)
VALID_BASE = {
    "domain": "diners",
    "environment": "dev",
    "workload": "channels",
    "region_code": "use1",
    "saml_resource_code": "saml",
    "max_session_duration": 3600,
    "instance_arn": VALID_ARN,
}


def test_harness_accepts_valid_input(workspace: FixtureWorkspace) -> None:
    result = workspace.plan(VALID_BASE)
    assert result.accepted, result.error
    assert result.output("role_federation") == (
        "dcp-diners-dev-channels-role-connect-federation"
    )
    assert result.output("policy_federation") == (
        "dcp-diners-dev-channels-policy-connect-federation"
    )
    assert result.output("role_federation_ok") is True
    assert result.output("saml_audience") == strat.SAML_AUDIENCE


def test_harness_builds_relay_states(workspace: FixtureWorkspace) -> None:
    result = workspace.plan(VALID_BASE)
    assert result.accepted, result.error
    admin = result.output("admin_relay_state_url")
    agent = result.output("agent_relay_state_url")
    region, instance_id, dest_admin = strat.parse_relay_state(admin)
    _, _, dest_agent = strat.parse_relay_state(agent)
    assert region == "us-east-1"
    assert instance_id == "11111111-2222-3333-4444-555555555555"
    assert dest_admin == strat.RELAY_DEST_ADMIN
    assert dest_agent == strat.RELAY_DEST_AGENT
    assert result.output("federation_resource") == f"{VALID_ARN}/user/*"


def test_harness_rejects_session_over_3600(workspace: FixtureWorkspace) -> None:
    result = workspace.plan({**VALID_BASE, "max_session_duration": 7200})
    assert not result.accepted
    assert "max_session_duration" in result.error


def test_harness_rejects_invalid_environment(workspace: FixtureWorkspace) -> None:
    result = workspace.plan({**VALID_BASE, "environment": "prd"})
    assert not result.accepted
    assert "environment" in result.error


def test_smoke_check_helper() -> None:
    result = smoke_check()
    assert result.accepted, result.error


@settings(max_examples=25)
@given(st.sampled_from(strat.REGION_CODES))
def test_hypothesis_plumbing_runs(region_code: str) -> None:
    with FixtureWorkspace() as ws:
        result = ws.plan({**VALID_BASE, "region_code": region_code})
        assert result.accepted, result.error
