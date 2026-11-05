#!/usr/bin/env python3
# =============================================================================
# scan_stack_files.py  (repo: dcp-aws-diners-live)
#
# Escaner de archivos de stack `terragrunt.hcl` de la carpeta live/.
# Hace cumplir, sin desplegar nada, las reglas de iac-core-rules y del spec
# connect-instance-initial-build (Requisitos 1.8, 2.1, 2.2, 2.7, 13.2):
#
#   1. El `source` de cada módulo debe ser exactamente
#        git::ssh://git@github.com/Diners/dcp-terraform-modules.git
#          //modules/<categoria>/<modulo>?ref=<40 hex>
#      y ese SHA de 40 caracteres debe estar registrado en compatibility.yaml.
#      Se rechaza: rama, tag, SHA corto, SHA no registrado, Registry publico,
#      cualquier otro Git o URL (2.1, 2.2).
#   2. Ningun ID de cuenta de 12 digitos en el archivo de stack (2.7, 13.2).
#   3. Ningun ARN literal (2.7, 13.2).
#   4. Ningun CIDR literal (2.7, 13.2).
#   5. Ningun literal de nombre de entorno (dev|qa|stg|prod) fuera de la
#      expresion `include.root.locals.environment` (13.2).
#   6. Ningun uso de `terraform_remote_state` (1.8).
#   7. Ningun uso de workspaces de Terraform CLI (1.8).
#
# Es solo de lectura. No ejecuta Terraform ni Terragrunt, no toca AWS y no
# depende de librerias externas (solo biblioteca estandar).
#
# Contrato de codigos de salida:
#   0  -> no se hallaron violaciones en ningun archivo escaneado.
#   1  -> se hallo al menos una violacion.
#   2  -> error de uso o de entorno (archivo/carpeta inexistente,
#         compatibility.yaml ilegible, argumentos invalidos).
#
# Uso:
#   python scripts/ci/scan_stack_files.py                 # escanea ./live
#   python scripts/ci/scan_stack_files.py live/contactcenter-dev
#   python scripts/ci/scan_stack_files.py a/terragrunt.hcl b/terragrunt.hcl
#   python scripts/ci/scan_stack_files.py --compatibility path/to/compatibility.yaml
#   python scripts/ci/scan_stack_files.py --json
# =============================================================================

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# -----------------------------------------------------------------------------
# Patrones
# -----------------------------------------------------------------------------

# Fuente de modulo aprobada. El prefijo Git+host+ruta es fijo; solo varian
# <categoria>/<modulo> y el ref. Se captura el ref para validarlo aparte, de
# modo que un ref invalido (rama, tag, SHA corto) produzca un mensaje claro.
_MODULES_HOST = r"git::ssh://git@github\.com/Diners/dcp-terraform-modules\.git"
_MODULE_PATH = r"//modules/[a-z0-9]+(?:-[a-z0-9]+)*/[a-z0-9]+(?:-[a-z0-9]+)*"

# Cualquier valor de `source = "..."` dentro de un bloque terraform.
SOURCE_ASSIGN_RE = re.compile(r'\bsource\s*=\s*"([^"]*)"')

# Fuente aprobada completa, con ref de exactamente 40 caracteres hex.
APPROVED_SOURCE_RE = re.compile(
    r"^" + _MODULES_HOST + _MODULE_PATH + r"\?ref=([0-9a-fA-F]{40})$"
)

# Prefijo del host/repo correcto (para distinguir "ref malo" de "origen ajeno").
MODULES_REPO_PREFIX_RE = re.compile(_MODULES_HOST)

# ID de cuenta AWS: 12 digitos consecutivos no rodeados de otros digitos.
ACCOUNT_ID_RE = re.compile(r"(?<!\d)\d{12}(?!\d)")

# ARN literal.
ARN_RE = re.compile(r"\barn:aws[a-z-]*:[^\s\"']*")

# CIDR IPv4: x.x.x.x/nn (cada octeto 0-255, prefijo 0-32).
CIDR_RE = re.compile(
    r"\b(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}"
    r"(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)/(?:3[0-2]|[12]?\d)\b"
)

# Uso prohibido de estado remoto y de workspaces de CLI.
REMOTE_STATE_RE = re.compile(r"\bterraform_remote_state\b")
WORKSPACE_RE = re.compile(
    r"\bterraform\s+workspace\b"            # comando CLI
    r"|\bterraform\.workspace\b"            # interpolacion
    r"|\$\{\s*terraform\.workspace\s*\}"    # interpolacion con llaves
)

# Expresion permitida que resuelve el entorno desde la jerarquia. Cualquier
# aparicion de dev/qa/stg/prod que no sea esta expresion es un literal.
ENV_EXPR_RE = re.compile(r"include\.root\.locals\.environment")

# Nombre de entorno como token aislado (no como subcadena de otra palabra).
ENV_LITERAL_RE = re.compile(r"(?<![A-Za-z0-9_-])(dev|qa|stg|prod)(?![A-Za-z0-9_-])")

# Nombre de archivo de stack que escaneamos.
STACK_FILENAME = "terragrunt.hcl"

# Archivos de jerarquia; NO son stacks y no se escanean como tales.
HIERARCHY_FILES = {"account.hcl", "env.hcl", "region.hcl", "app.hcl", "domain.hcl", "state.hcl"}


# -----------------------------------------------------------------------------
# Modelo de resultados
# -----------------------------------------------------------------------------


@dataclass
class Violation:
    file: str
    line: int
    rule: str
    message: str

    def as_text(self) -> str:
        return f"{self.file}:{self.line}: [{self.rule}] {self.message}"

    def as_dict(self) -> dict:
        return {
            "file": self.file,
            "line": self.line,
            "rule": self.rule,
            "message": self.message,
        }


@dataclass
class ScanResult:
    violations: list[Violation] = field(default_factory=list)
    files_scanned: int = 0


# -----------------------------------------------------------------------------
# Utilidades de texto
# -----------------------------------------------------------------------------


def strip_comment(line: str) -> str:
    """Quita el comentario de linea que empieza por '#' o '//', respetando
    comillas. No intenta manejar heredocs ni comentarios de bloque /* */,
    que no se usan en los archivos de stack de este repo."""
    out = []
    in_str = False
    quote = ""
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if in_str:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(line[i + 1])
                i += 2
                continue
            if ch == quote:
                in_str = False
            i += 1
            continue
        if ch in ('"', "'"):
            in_str = True
            quote = ch
            out.append(ch)
            i += 1
            continue
        if ch == "#":
            break
        if ch == "/" and i + 1 < n and line[i + 1] == "/":
            break
        out.append(ch)
        i += 1
    return "".join(out)


def mask_env_expr(text: str) -> str:
    """Reemplaza la expresion permitida include.root.locals.environment por
    espacios equivalentes, para que la busqueda de literales de entorno no la
    confunda con el nombre 'environment' ni con un literal."""
    return ENV_EXPR_RE.sub(lambda m: " " * (m.end() - m.start()), text)


# -----------------------------------------------------------------------------
# Carga de SHAs registrados en compatibility.yaml
# -----------------------------------------------------------------------------

_SHA_IN_YAML_RE = re.compile(r"^\s*sha\s*:\s*([0-9a-fA-F]{40})\b", re.MULTILINE)


def load_registered_shas(compatibility_path: Path | None) -> set[str]:
    """Devuelve el conjunto de SHAs de 40 hex declarados en compatibility.yaml.

    Se parsea con una expresion regular sobre las lineas `sha: <40hex>` para no
    exigir PyYAML en el runner (solo-Nexus, biblioteca estandar). Si el archivo
    no existe o no es legible se lanza FileNotFoundError/OSError, que el llamador
    traduce a codigo de salida 2. Si la ruta es None, no se puede validar el
    registro y se devuelve un conjunto vacio; en ese caso toda fuente, aun con
    forma correcta, se marca como 'SHA no verificable'."""
    if compatibility_path is None:
        return set()
    content = compatibility_path.read_text(encoding="utf-8")
    return {m.group(1).lower() for m in _SHA_IN_YAML_RE.finditer(content)}


# -----------------------------------------------------------------------------
# Escaneo de un archivo
# -----------------------------------------------------------------------------


def scan_text(
    rel_name: str,
    text: str,
    registered_shas: set[str],
    compatibility_available: bool,
) -> list[Violation]:
    violations: list[Violation] = []
    lines = text.splitlines()

    for idx, raw_line in enumerate(lines, start=1):
        code = strip_comment(raw_line)
        if not code.strip():
            continue

        # --- 1. Fuente de modulo ------------------------------------------
        for m in SOURCE_ASSIGN_RE.finditer(code):
            src = m.group(1)
            _check_source(
                rel_name, idx, src, registered_shas,
                compatibility_available, violations,
            )

        # --- 6/7. estado remoto y workspaces (antes de enmascarar) --------
        if REMOTE_STATE_RE.search(code):
            violations.append(Violation(
                rel_name, idx, "remote-state",
                "uso de terraform_remote_state prohibido; comparta contratos por SSM (L05, 1.8)",
            ))
        if WORKSPACE_RE.search(code):
            violations.append(Violation(
                rel_name, idx, "workspace",
                "uso de workspaces de Terraform CLI prohibido para separar entornos (L05, 1.8)",
            ))

        # Para los literales, trabajamos sobre el codigo sin la expresion de
        # entorno permitida, para no marcarla como falso positivo.
        masked = mask_env_expr(code)

        # --- 2. ID de cuenta de 12 digitos --------------------------------
        for am in ACCOUNT_ID_RE.finditer(masked):
            violations.append(Violation(
                rel_name, idx, "account-id",
                f"ID de cuenta de 12 digitos '{am.group(0)}' en archivo de stack; "
                f"los IDs viven en account.hcl/accounts.yaml (2.7, 13.2)",
            ))

        # --- 3. ARN literal -----------------------------------------------
        for arm in ARN_RE.finditer(masked):
            violations.append(Violation(
                rel_name, idx, "arn",
                f"ARN literal '{arm.group(0)}' en archivo de stack; "
                f"lealo de un contrato SSM, no lo escriba (2.7, 13.2)",
            ))

        # --- 4. CIDR literal ----------------------------------------------
        for cm in CIDR_RE.finditer(masked):
            violations.append(Violation(
                rel_name, idx, "cidr",
                f"CIDR literal '{cm.group(0)}' en archivo de stack; "
                f"los CIDR vienen de IPAM por SSM/RAM (2.7, 13.2)",
            ))

        # --- 5. Literal de nombre de entorno ------------------------------
        for em in ENV_LITERAL_RE.finditer(masked):
            violations.append(Violation(
                rel_name, idx, "env-literal",
                f"literal de entorno '{em.group(1)}' en archivo de stack; "
                f"use include.root.locals.environment (13.2)",
            ))

    return violations


def _check_source(
    rel_name: str,
    idx: int,
    src: str,
    registered_shas: set[str],
    compatibility_available: bool,
    violations: list[Violation],
) -> None:
    approved = APPROVED_SOURCE_RE.match(src)
    if approved is None:
        # Forma incorrecta. Distinguir origen ajeno de ref invalido.
        if MODULES_REPO_PREFIX_RE.match(src):
            reason = (
                "ref invalido; se exige ?ref=<40 hex> (ni rama, ni tag, ni SHA corto)"
            )
        else:
            reason = (
                "origen no aprobado; use "
                "git::ssh://git@github.com/Diners/dcp-terraform-modules.git"
                "//modules/<categoria>/<modulo>?ref=<40 hex>"
            )
        violations.append(Violation(
            rel_name, idx, "module-source",
            f"source '{src}' {reason} (2.1, 2.2)",
        ))
        return

    sha = approved.group(1).lower()
    if not compatibility_available:
        violations.append(Violation(
            rel_name, idx, "module-sha",
            f"SHA '{sha}' no verificable: no se proporciono compatibility.yaml (2.1)",
        ))
        return
    if sha not in registered_shas:
        violations.append(Violation(
            rel_name, idx, "module-sha",
            f"SHA '{sha}' no esta registrado en compatibility.yaml (2.1, 2.2)",
        ))


# -----------------------------------------------------------------------------
# Descubrimiento de archivos
# -----------------------------------------------------------------------------


def collect_stack_files(targets: list[Path]) -> list[Path]:
    """Expande los objetivos a archivos de stack terragrunt.hcl.

    - Un archivo se toma tal cual (debe llamarse terragrunt.hcl).
    - Una carpeta se recorre buscando todos los terragrunt.hcl que no sean el
      terragrunt.hcl raiz del repo (ese esta fuera de live/ y no es un stack).
    """
    files: list[Path] = []
    seen: set[Path] = set()
    for target in targets:
        if target.is_file():
            resolved = target.resolve()
            if resolved not in seen:
                seen.add(resolved)
                files.append(target)
        elif target.is_dir():
            for found in sorted(target.rglob(STACK_FILENAME)):
                # El terragrunt.hcl raiz vive junto a domain.hcl/state.hcl y no
                # es un stack; solo escaneamos los que estan bajo live/.
                if "live" not in found.parts:
                    continue
                resolved = found.resolve()
                if resolved not in seen:
                    seen.add(resolved)
                    files.append(found)
        else:
            raise FileNotFoundError(str(target))
    return files


def _display_name(path: Path) -> str:
    try:
        return path.relative_to(Path.cwd()).as_posix()
    except ValueError:
        return path.as_posix()


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------


def run(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Escanea archivos de stack terragrunt.hcl y rechaza fuentes de "
            "modulo no aprobadas y literales prohibidos (IDs de cuenta, ARNs, "
            "CIDRs, nombres de entorno), terraform_remote_state y workspaces."
        )
    )
    parser.add_argument(
        "paths",
        nargs="*",
        default=["live"],
        help="archivos terragrunt.hcl o carpetas a escanear (por defecto: live)",
    )
    parser.add_argument(
        "--compatibility",
        default=None,
        help=(
            "ruta a compatibility.yaml de dcp-terraform-modules. Si se omite, "
            "se autodetecta junto a los objetivos; si no se halla, los SHA no "
            "se pueden verificar y se marcan como tales."
        ),
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="emite el resultado como JSON en stdout",
    )
    args = parser.parse_args(argv)

    targets = [Path(p) for p in (args.paths or ["live"])]

    # Resolver compatibility.yaml.
    compatibility_path: Path | None = None
    if args.compatibility:
        compatibility_path = Path(args.compatibility)
        if not compatibility_path.is_file():
            print(
                f"error: compatibility.yaml no encontrado en '{compatibility_path}'",
                file=sys.stderr,
            )
            return 2

    try:
        registered_shas = load_registered_shas(compatibility_path)
    except OSError as exc:
        print(f"error: no se pudo leer compatibility.yaml: {exc}", file=sys.stderr)
        return 2
    compatibility_available = compatibility_path is not None

    try:
        stack_files = collect_stack_files(targets)
    except FileNotFoundError as exc:
        print(f"error: ruta inexistente: {exc}", file=sys.stderr)
        return 2

    result = ScanResult()
    for path in stack_files:
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"error: no se pudo leer {path}: {exc}", file=sys.stderr)
            return 2
        result.files_scanned += 1
        result.violations.extend(
            scan_text(_display_name(path), text, registered_shas, compatibility_available)
        )

    # Salida.
    if args.json:
        payload = {
            "files_scanned": result.files_scanned,
            "violation_count": len(result.violations),
            "violations": [v.as_dict() for v in result.violations],
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        for v in result.violations:
            print(v.as_text())
        if result.violations:
            print(
                f"\n{len(result.violations)} violacion(es) en "
                f"{result.files_scanned} archivo(s) de stack escaneado(s).",
                file=sys.stderr,
            )
        else:
            print(
                f"OK: {result.files_scanned} archivo(s) de stack sin violaciones."
            )

    return 1 if result.violations else 0


def main() -> None:
    sys.exit(run(sys.argv[1:]))


if __name__ == "__main__":
    main()
