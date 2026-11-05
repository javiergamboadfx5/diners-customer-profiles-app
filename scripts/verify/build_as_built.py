#!/usr/bin/env python3
"""build_as_built.py

Builds the as-built record for the dev Connect instance (Requirements 14.4 and
14.6, PCI decision OQ-6). Standard library only. Makes no AWS calls.

Inputs:
  --evidence AREA=PATH   One JSONL file per verification area. Repeat for each
                         of the three areas: instance (verify-instance),
                         profiles (verify-profiles), saml (verify-saml). Each
                         line is a JSON object with the keys check, expected,
                         actual, result and timestamp. Each area maps to its
                         Stack: instance -> instance, profiles ->
                         customer-profiles, saml -> saml-federation.
  --ssm-values PATH      JSON object with the SSM output values and record
                         fields listed in REQUIRED_VALUES below.
  --pci-decision VALUE   OQ-6 decision: in-scope or out-of-scope. Required.
  --pci-reference TEXT   Optional reference to the Ciberseguridad decision.
  --format md|json       Output format. Default md.
  --output PATH          File to write the as-built record to.

Exit codes:
  0  Record written. Every check passed, all three areas have evidence, and
     the PCI decision is present.
  1  Refused. The environment is not marked as-built and no output is written.
  2  Usage or file error.

Refusal reasons are printed to stderr. Any failed check, a missing area, an
empty area file, a missing PCI decision or a missing SSM value causes refusal.

Example:
  python scripts/verify/build_as_built.py \
    --evidence instance=evidence/verify-instance.jsonl \
    --evidence profiles=evidence/verify-profiles.jsonl \
    --evidence saml=evidence/verify-saml.jsonl \
    --ssm-values evidence/ssm-values.json \
    --pci-decision out-of-scope \
    --output evidence/as-built.md
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

AREAS = {
    "instance": "instance",
    "profiles": "customer-profiles",
    "saml": "saml-federation",
}

PCI_DECISIONS = ("in-scope", "out-of-scope")

EVIDENCE_KEYS = ("check", "expected", "actual", "result", "timestamp")

# Keys the SSM values file must provide. Names match the SSM_Contract leaf
# names in design.md where a contract exists. The rest are record fields
# published by the stacks (SAML outputs, key aliases, access URL, account).
REQUIRED_VALUES = (
    "account-id",
    "region",
    "instance-alias",
    "identity-management-type",
    "connect-instance-id",
    "connect-instance-arn",
    "access-url",
    "connect-storage-bucket-name",
    "connect-kms-key-arn",
    "storage-key-alias",
    "customer-profiles-kms-key-arn",
    "customer-profiles-key-alias",
    "customer-profiles-domain-name",
    "customer-profiles-domain-arn",
    "saml-provider-arn",
    "saml-role-arn",
    "stack-paths",
)


def load_evidence(area: str, path: Path, problems: list[str]) -> list[dict] | None:
    """Parse one JSONL evidence file. Appends refusal reasons to problems."""
    if not path.is_file():
        problems.append(f"{area}: evidence file not found: {path}")
        return None

    checks: list[dict] = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        try:
            entry = json.loads(raw)
        except json.JSONDecodeError as exc:
            problems.append(f"{area}: line {number} is not valid JSON ({exc.msg})")
            continue
        if not isinstance(entry, dict):
            problems.append(f"{area}: line {number} is not a JSON object")
            continue
        missing = [k for k in EVIDENCE_KEYS if k not in entry]
        if missing:
            problems.append(f"{area}: line {number} lacks fields {', '.join(missing)}")
            continue
        if entry["result"] != "pass":
            problems.append(
                f"{area}: check '{entry['check']}' has result {entry['result']!r}, expected 'pass'"
            )
        checks.append(entry)

    if not checks:
        problems.append(f"{area}: evidence file has no checks: {path}")
        return None
    return checks


def load_values(path: Path, problems: list[str]) -> dict | None:
    """Load the SSM values JSON and check that every required value is present."""
    if not path.is_file():
        problems.append(f"SSM values file not found: {path}")
        return None
    try:
        values = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        problems.append(f"SSM values file is not valid JSON ({exc.msg})")
        return None
    if not isinstance(values, dict):
        problems.append("SSM values file must be a JSON object")
        return None

    for key in REQUIRED_VALUES:
        value = values.get(key)
        if value is None or value == "" or value == {} or value == []:
            problems.append(f"SSM value missing: {key}")
    return values


def sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render_markdown(record: dict) -> str:
    v = record["values"]
    lines: list[str] = []
    lines.append("# As-built record: dev Connect instance")
    lines.append("")
    lines.append(f"Generated (UTC): {record['generated_at']}")
    lines.append("")
    lines.append("## Environment (Requirement 14.6)")
    lines.append("")
    lines.append(f"- Stack paths: {json.dumps(v['stack-paths'], ensure_ascii=False)}")
    lines.append(f"- Account: {v['account-id']}")
    lines.append(f"- Region: {v['region']}")
    lines.append(f"- Instance alias: {v['instance-alias']}")
    lines.append(f"- Identity management type: {v['identity-management-type']}")
    lines.append(f"- Instance ID: {v['connect-instance-id']}")
    lines.append(f"- Instance ARN: {v['connect-instance-arn']}")
    lines.append(f"- Access URL: {v['access-url']}")
    lines.append(f"- Storage bucket: {v['connect-storage-bucket-name']}")
    lines.append(f"- Storage key alias: {v['storage-key-alias']}")
    lines.append(f"- Storage key ARN: {v['connect-kms-key-arn']}")
    lines.append(f"- Customer Profiles key alias: {v['customer-profiles-key-alias']}")
    lines.append(f"- Customer Profiles key ARN: {v['customer-profiles-kms-key-arn']}")
    lines.append(f"- Customer Profiles domain: {v['customer-profiles-domain-name']}")
    lines.append(f"- Customer Profiles domain ARN: {v['customer-profiles-domain-arn']}")
    lines.append(f"- SAML provider ARN: {v['saml-provider-arn']}")
    lines.append(f"- SAML role ARN: {v['saml-role-arn']}")
    lines.append("")
    lines.append("## PCI decision (OQ-6)")
    lines.append("")
    lines.append(f"- Decision: {record['pci_decision']}")
    lines.append(f"- Reference: {record['pci_reference'] or 'not provided'}")
    lines.append("")
    lines.append("## Verification evidence (Requirement 14.4)")
    lines.append("")
    for area, info in record["evidence"].items():
        lines.append(f"### {area} (stack: {info['stack']})")
        lines.append("")
        lines.append(f"- Source: {info['source']}")
        lines.append(f"- SHA-256: {info['sha256']}")
        lines.append(f"- Checks: {info['count']}, all passed")
        lines.append("")
        for check in info["checks"]:
            lines.append(
                f"- {check['check']}: expected {check['expected']}, "
                f"actual {check['actual']}, result {check['result']} ({check['timestamp']})"
            )
        lines.append("")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--evidence", action="append", default=[], metavar="AREA=PATH",
                        help="Evidence JSONL for one area: instance, profiles or saml.")
    parser.add_argument("--ssm-values", metavar="PATH", help="JSON file with the SSM output values.")
    parser.add_argument("--pci-decision", metavar="VALUE", help="in-scope or out-of-scope (OQ-6).")
    parser.add_argument("--pci-reference", default="", help="Reference to the Ciberseguridad decision.")
    parser.add_argument("--format", choices=("md", "json"), default="md")
    parser.add_argument("--output", metavar="PATH", help="File to write the as-built record to.")
    args = parser.parse_args(argv)

    if not args.output:
        print("build_as_built: --output is required", file=sys.stderr)
        return 2
    if not args.ssm_values:
        print("build_as_built: --ssm-values is required", file=sys.stderr)
        return 2

    problems: list[str] = []

    # Evidence: exactly one file per area, all three areas.
    evidence_paths: dict[str, Path] = {}
    for item in args.evidence:
        if "=" not in item:
            print(f"build_as_built: --evidence must be AREA=PATH, got {item!r}", file=sys.stderr)
            return 2
        area, _, raw_path = item.partition("=")
        if area not in AREAS:
            print(f"build_as_built: unknown area {area!r}; use instance, profiles or saml", file=sys.stderr)
            return 2
        if area in evidence_paths:
            problems.append(f"{area}: evidence given more than once")
        evidence_paths[area] = Path(raw_path)

    for area in AREAS:
        if area not in evidence_paths:
            problems.append(f"{area}: evidence missing (no --evidence {area}=PATH)")

    # PCI decision is an explicit input. Absence refuses the record.
    if not args.pci_decision:
        problems.append("PCI decision (OQ-6) missing: pass --pci-decision in-scope or out-of-scope")
    elif args.pci_decision not in PCI_DECISIONS:
        problems.append(f"PCI decision (OQ-6) must be in-scope or out-of-scope, got {args.pci_decision!r}")

    values = load_values(Path(args.ssm_values), problems)

    evidence: dict[str, dict] = {}
    for area, stack in AREAS.items():
        if area not in evidence_paths:
            continue
        path = evidence_paths[area]
        checks = load_evidence(area, path, problems)
        if checks is None:
            continue
        evidence[area] = {
            "stack": stack,
            "source": str(path),
            "sha256": sha256_of(path),
            "count": len(checks),
            "checks": checks,
        }

    if problems:
        print("build_as_built: REFUSED. The environment is not marked as-built.", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    record = {
        "status": "as-built",
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "pci_decision": args.pci_decision,
        "pci_reference": args.pci_reference,
        "values": {key: values[key] for key in REQUIRED_VALUES},
        "evidence": evidence,
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    if args.format == "json":
        output.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    else:
        output.write_text(render_markdown(record), encoding="utf-8")
    print(f"build_as_built: wrote as-built record to {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
