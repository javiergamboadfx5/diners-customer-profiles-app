"""Shared Hypothesis strategies and reference predicates.

Feature: connect-instance-initial-build (task 1.5).

Task 1.5 establishes the shared generator setup that the SAML property tests
(tasks 4.2, 4.3 and the cross-module environment test 1.7) plug into. Each
property test imports the relevant strategy and reference predicate from here,
so the input space and the expected acceptance rule live in one place.
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
EXCEPTION_RE = re.compile(r"^exc-cloud-[0-9]{4}-[0-9]{4}$")
SAML_CODE_RE = re.compile(r"^[a-z][a-z0-9-]*[a-z0-9]$")
INSTANCE_ARN_RE = re.compile(
    r"^arn:aws[a-z-]*:connect:[a-z0-9-]+:[0-9]{12}:instance/"
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
)

SAML_AUDIENCE = "https://signin.aws.amazon.com/saml"
RELAY_DEST_ADMIN = "%2Fconnect"
RELAY_DEST_AGENT = "%2Fagent-app-v2"

# Role session duration bounds enforced by validations.tf.
SESSION_MIN = 900
SESSION_MAX = 3600


# ---------------------------------------------------------------------------
# Reference predicates
# ---------------------------------------------------------------------------

def environment_valid(value: str) -> bool:
    return value in ENVIRONMENTS


def workload_valid(value: str) -> bool:
    return bool(WORKLOAD_RE.fullmatch(value))


def session_duration_valid(value: int) -> bool:
    return SESSION_MIN <= value <= SESSION_MAX


def instance_arn_valid(value: str) -> bool:
    return bool(INSTANCE_ARN_RE.fullmatch(value))


def saml_code_valid(value: str) -> bool:
    return bool(SAML_CODE_RE.fullmatch(value))


def metadata_valid(value: str) -> bool:
    return value.strip() != "" and "EntityDescriptor" in value


def parse_relay_state(url: str) -> tuple[str, str, str]:
    """Return (region, instance_id, destination) parsed from a relay state URL."""
    m = re.match(
        r"^https://(?P<region>[a-z0-9-]+)\.console\.aws\.amazon\.com/connect/"
        r"federate/(?P<id>[0-9a-f-]+)\?destination=(?P<dest>.+)$",
        url,
    )
    if not m:
        raise ValueError(f"unparseable relay state: {url}")
    return m.group("region"), m.group("id"), m.group("dest")


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


def saml_codes() -> st.SearchStrategy[str]:
    return st.from_regex(SAML_CODE_RE, fullmatch=True).filter(lambda s: len(s) <= 20)


def session_durations() -> st.SearchStrategy[int]:
    """Integers around the [900, 3600] window, including invalid values."""
    return st.integers(min_value=300, max_value=5000)


def account_ids() -> st.SearchStrategy[str]:
    return st.from_regex(r"^[0-9]{12}$", fullmatch=True)


def instance_uuids() -> st.SearchStrategy[str]:
    return st.from_regex(
        r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
        fullmatch=True,
    )


@st.composite
def instance_arns(draw) -> str:
    region = draw(region_full_names())
    account = draw(account_ids())
    uuid = draw(instance_uuids())
    return f"arn:aws:connect:{region}:{account}:instance/{uuid}"


def region_full_names() -> st.SearchStrategy[str]:
    return st.sampled_from(["us-east-1", "us-east-2", "us-west-2", "sa-east-1"])
