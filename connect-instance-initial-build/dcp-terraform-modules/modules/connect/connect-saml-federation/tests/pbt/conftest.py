"""Shared pytest fixtures and Hypothesis profile for the PBT harness.

Feature: connect-instance-initial-build (task 1.5).

A single :class:`FixtureWorkspace` is built once per test session and reused by
every property test, so the one-off ``terraform init`` cost is amortized across
all examples. The ``ci`` Hypothesis profile sets ``max_examples = 100`` as the
design requires; it is selected by default and can be overridden with
``--hypothesis-profile=dev`` for a faster local loop.
"""

from __future__ import annotations

import shutil

import pytest
from hypothesis import HealthCheck, settings

from harness import FixtureWorkspace

settings.register_profile(
    "ci",
    max_examples=100,
    deadline=None,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.function_scoped_fixture],
)
settings.register_profile(
    "dev",
    max_examples=20,
    deadline=None,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.function_scoped_fixture],
)
settings.load_profile("ci")


def _terraform_available() -> bool:
    return shutil.which("terraform") is not None


@pytest.fixture(scope="session")
def workspace() -> FixtureWorkspace:
    if not _terraform_available():
        pytest.skip("terraform not found on PATH; cannot run the PBT harness")
    ws = FixtureWorkspace()
    yield ws
    ws.close()
