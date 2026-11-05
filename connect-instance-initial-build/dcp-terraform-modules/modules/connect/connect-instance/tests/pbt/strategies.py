"""Shared Hypothesis strategies and reference predicates.

Feature: connect-instance-initial-build (task 1.5).

Task 1.5 establishes the shared generator setup that the property tests
(tasks 1.6-1.12) plug into. Each property test imports the relevant strategy
and reference predicate from here, so the input space and the expected
acceptance rule live in one place.

The strategies deliberately bias toward the edges of each input space (empty
strings, boundary lengths, leading/trailing hyphens, off-by-one numeric
bounds) because those are where the Terraform validations are most likely to
be wrong.
"""

from __future__ import annotations

import re

from hypothesis import strategies as st

# ---------------------------------------------------------------------------
# Canonical rules (kept in sync with validations.tf / naming.tf)
# ---------------------------------------------------------------------------

ALIAS_RE = re.compile(r"^[a-z0-9]([a-z0-9-]{0,60}[a-z0-9])?$")
WORKLOAD_RE = re.compile(r"^[a-z][a-z0-9]{1,9}$")
EXCEPTION_RE = re.compile(r"^exc-cloud-[0-9]{4}-[0-9]{4}$")

ENVIRONMENTS = ("dev", "qa", "stg", "prod")
IDENTITY_TYPES = ("SAML", "CONNECT_MANAGED", "EXISTING_DIRECTORY")
REGION_CODES = ("use1", "use2", "usw2", "sae1")

# CloudWatch Logs allowed retention values (0 == never expire, forbidden).
CLOUDWATCH_RETENTION = (
    1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731,
    1096, 1827, 2192, 2557, 2922, 3288, 3653,
)


# ---------------------------------------------------------------------------
# Reference predicates (the "if and only if" oracle for each rule)
# ---------------------------------------------------------------------------

def alias_valid(value: str) -> bool:
    return bool(ALIAS_RE.fullmatch(value))


def environment_valid(value: str) -> bool:
    return value in ENVIRONMENTS


def workload_valid(value: str) -> bool:
    return bool(WORKLOAD_RE.fullmatch(value))


def exception_id_well_formed(value: str) -> bool:
    return bool(EXCEPTION_RE.fullmatch(value))


def flow_log_retention_valid(value: int) -> bool:
    return value in CLOUDWATCH_RETENTION


# ---------------------------------------------------------------------------
# Hypothesis strategies
# ---------------------------------------------------------------------------

# A mix of certainly-valid and likely-invalid alias candidates.
_alias_chars = st.sampled_from("abcdefghijklmnopqrstuvwxyz0123456789-")


@st.composite
def aliases(draw) -> str:
    """Strings aimed at the alias regex edges (length 0..64, hyphen edges)."""
    length = draw(st.integers(min_value=0, max_value=64))
    return "".join(draw(_alias_chars) for _ in range(length))


def valid_aliases() -> st.SearchStrategy[str]:
    return st.from_regex(ALIAS_RE, fullmatch=True).filter(lambda s: 1 <= len(s) <= 62)


def environments(include_invalid: bool = True) -> st.SearchStrategy[str]:
    valid = st.sampled_from(ENVIRONMENTS)
    if not include_invalid:
        return valid
    bogus = st.sampled_from(
        ["prd", "production", "development", "sbx", "test", "", "DEV", "qas"]
    )
    return st.one_of(valid, bogus)


def identity_types(include_invalid: bool = True) -> st.SearchStrategy[str]:
    valid = st.sampled_from(IDENTITY_TYPES)
    if not include_invalid:
        return valid
    bogus = st.sampled_from(["saml", "connect", "AD", "", "EXISTING"])
    return st.one_of(valid, bogus)


def workloads() -> st.SearchStrategy[str]:
    return st.from_regex(WORKLOAD_RE, fullmatch=True)


def region_codes() -> st.SearchStrategy[str]:
    return st.sampled_from(REGION_CODES)


def org_ids() -> st.SearchStrategy[str]:
    return st.from_regex(r"^o-[a-z0-9]{10,32}$", fullmatch=True)


def account_ids() -> st.SearchStrategy[str]:
    return st.from_regex(r"^[0-9]{12}$", fullmatch=True)


def exception_ids(include_invalid: bool = True) -> st.SearchStrategy[str]:
    valid = st.from_regex(EXCEPTION_RE, fullmatch=True)
    if not include_invalid:
        return valid
    bogus = st.sampled_from(
        ["", "exc-cloud-1-1", "exc-2026-0001", "exc-cloud-20260-001", "nope"]
    )
    return st.one_of(valid, bogus)


def retention_days() -> st.SearchStrategy[int]:
    """Integers around the `>= 1` boundary, including invalid values."""
    return st.integers(min_value=-5, max_value=4000)


def flow_log_retention() -> st.SearchStrategy[int]:
    """Mix of allowed CloudWatch values and nearby invalid ones (incl. 0)."""
    return st.one_of(
        st.sampled_from(CLOUDWATCH_RETENTION),
        st.sampled_from([0, 2, 4, 15, 31, 100, 366, 3654]),
    )
