"""Shared Hypothesis strategies and reference predicates.

Feature: connect-instance-initial-build (task 1.5).

Task 1.5 establishes the shared generator setup that the Profiles property
tests (tasks 1.9, 1.10, 1.11, and the cross-module environment test 1.7) plug
into. Each property test imports the relevant strategy and reference predicate
from here, so the input space and the expected acceptance rule live in one
place.
"""

from __future__ import annotations

import re

from hypothesis import strategies as st

# ---------------------------------------------------------------------------
# Canonical rules (kept in sync with validations.tf / naming.tf)
# ---------------------------------------------------------------------------

ENVIRONMENTS = ("dev", "qa", "stg", "prod")
REGION_CODES = ("use1", "use2", "usw2", "sae1")
WORKLOAD_RE = re.compile(r"^[a-z][a-z0-9]{1,9}$")
DOMAIN_PREFIX = "amazon-connect-"
DOMAIN_CHARS_RE = re.compile(r"^[A-Za-z0-9_-]+$")
DOMAIN_MAX_LEN = 64

EXPIRATION_MIN = 1
EXPIRATION_MAX = 1098


# ---------------------------------------------------------------------------
# Reference predicates
# ---------------------------------------------------------------------------

def environment_valid(value: str) -> bool:
    return value in ENVIRONMENTS


def workload_valid(value: str) -> bool:
    return bool(WORKLOAD_RE.fullmatch(value))


def domain_name_valid(value: str) -> bool:
    return (
        value.startswith(DOMAIN_PREFIX)
        and len(value) <= DOMAIN_MAX_LEN
        and bool(DOMAIN_CHARS_RE.fullmatch(value))
    )


def expiration_valid(value: int) -> bool:
    return (
        isinstance(value, int)
        and EXPIRATION_MIN <= value <= EXPIRATION_MAX
    )


def data_store_pair_valid(enable: bool, approval_ref: str) -> bool:
    return (not enable) or approval_ref.strip() != ""


def expected_domain(environment: str, workload: str, domain: str = "diners") -> str:
    """Mirror naming.tf: amazon-connect-dcp-<domain>-<env>-<workload>."""
    return f"{DOMAIN_PREFIX}dcp-{domain}-{environment}-{workload}"


# ---------------------------------------------------------------------------
# Hypothesis strategies
# ---------------------------------------------------------------------------

def environments(include_invalid: bool = True) -> st.SearchStrategy[str]:
    valid = st.sampled_from(ENVIRONMENTS)
    if not include_invalid:
        return valid
    bogus = st.sampled_from(["prd", "production", "development", "", "DEV", "qas"])
    return st.one_of(valid, bogus)


def region_codes() -> st.SearchStrategy[str]:
    return st.sampled_from(REGION_CODES)


def workloads() -> st.SearchStrategy[str]:
    return st.from_regex(WORKLOAD_RE, fullmatch=True)


def valid_domain_names() -> st.SearchStrategy[str]:
    body = st.text(alphabet="abcdefghijklmnopqrstuvwxyz0123456789_-", min_size=0, max_size=40)
    return body.map(lambda s: DOMAIN_PREFIX + s).filter(domain_name_valid)


def domain_names(include_invalid: bool = True) -> st.SearchStrategy[str]:
    """Candidate domain names aimed at the three rule edges (prefix, length, charset)."""
    if not include_invalid:
        return valid_domain_names()
    missing_prefix = st.text(alphabet="abcdefghijklmnopqrstuvwxyz-", min_size=1, max_size=20)
    bad_char = st.just("amazon-connect-has space!")
    too_long = st.just(DOMAIN_PREFIX + "x" * 60)
    return st.one_of(valid_domain_names(), missing_prefix, bad_char, too_long)


def expiration_days() -> st.SearchStrategy[int]:
    """Integers around the [1, 1098] window, including out-of-range values."""
    return st.integers(min_value=-5, max_value=1200)


def approval_refs() -> st.SearchStrategy[str]:
    return st.sampled_from(["", "   ", "CUMP-2026-001", "aprobacion-lpdp-42"])
