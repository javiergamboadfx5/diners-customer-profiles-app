#!/usr/bin/env python3
# Comparador de promoción entre carpetas de entorno (contactcenter-<env>).
# Feature: connect-instance-initial-build
# Requisitos: 13.1, 13.5
#
# Verifica la condición de "promotion ready" del diseño: cada archivo de Stack
# (p. ej. `terragrunt.hcl`) debe ser byte-idéntico entre dos carpetas
# `live/contactcenter-<env>`, ignorando únicamente los Hierarchy_Files, que son
# los que legítimamente cambian por entorno (account.hcl, env.hcl, region.hcl,
# app.hcl).
#
# Mientras Platform no adopte esto como check del Pipeline (OQ-16), se ejecuta
# como script del Live_Repo. No requiere credenciales ni red: solo lee archivos
# del árbol de trabajo y usa la biblioteca estándar.
#
# Uso:
#   python scripts/ci/compare_env_folders.py live/contactcenter-dev live/contactcenter-qa
#   python scripts/ci/compare_env_folders.py --json BASE OTRA
#
# Salida: 0 si los archivos de Stack son idénticos; 1 si hay diferencias; 2 si
# los argumentos o las rutas son inválidos.

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

# Archivos de jerarquía: contienen los valores específicos del entorno
# (account_key, environment, region, workload/owner/cost_center...). Se comparan
# por nombre de archivo en cualquier nivel de la carpeta de entorno, porque un
# cambio en ellos entre dev y qa es esperado y NO debe marcar la promoción.
HIERARCHY_FILES = frozenset({"account.hcl", "env.hcl", "region.hcl", "app.hcl"})

# Artefactos generados por Terragrunt o locales que no forman parte de la
# definición promovible del Stack. El .gitignore ya los excluye del repo
# (tarea 7.4), así que tampoco deben influir en la comparación aunque estén
# presentes en un árbol de trabajo local.
IGNORED_FILE_NAMES = frozenset({"backend.tf", "provider.tf", "import.tf"})
IGNORED_SUFFIXES = (".tfstate", ".tfstate.backup")
IGNORED_DIR_NAMES = frozenset({".terraform"})

# Tamaño de bloque para el hash incremental de archivos grandes.
_CHUNK = 65536


class ComparatorError(Exception):
    """Error de argumentos o de rutas (código de salida 2)."""


def is_hierarchy_file(relative: Path) -> bool:
    """True si la ruta relativa corresponde a un Hierarchy_File."""
    return relative.name in HIERARCHY_FILES


def is_ignored(relative: Path) -> bool:
    """True si la ruta relativa es un artefacto generado o local a ignorar."""
    if any(part in IGNORED_DIR_NAMES for part in relative.parts):
        return True
    if relative.name in IGNORED_FILE_NAMES:
        return True
    return relative.name.endswith(IGNORED_SUFFIXES)


def collect_stack_files(root: Path) -> dict[str, Path]:
    """Devuelve las rutas relativas (como texto POSIX) de los archivos de Stack.

    Excluye los Hierarchy_Files y los artefactos generados o locales. La clave
    es la ruta relativa a `root` normalizada con separadores `/`, de modo que la
    comparación sea estable entre sistemas operativos.
    """
    files: dict[str, Path] = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(root)
        if is_hierarchy_file(relative) or is_ignored(relative):
            continue
        files[relative.as_posix()] = path
    return files


def hash_file(path: Path) -> str:
    """SHA-256 del contenido en bytes del archivo (comparación byte a byte)."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(_CHUNK), b""):
            digest.update(block)
    return digest.hexdigest()


def compare_env_folders(base: Path, other: Path) -> dict:
    """Compara dos carpetas de entorno y devuelve el informe de diferencias.

    El informe incluye las listas de rutas de Stack solo presentes en una de las
    carpetas y las rutas presentes en ambas cuyo contenido no es byte-idéntico.
    """
    base_files = collect_stack_files(base)
    other_files = collect_stack_files(other)

    base_keys = set(base_files)
    other_keys = set(other_files)

    only_in_base = sorted(base_keys - other_keys)
    only_in_other = sorted(other_keys - base_keys)

    content_mismatch: list[str] = []
    for key in sorted(base_keys & other_keys):
        if hash_file(base_files[key]) != hash_file(other_files[key]):
            content_mismatch.append(key)

    identical = not (only_in_base or only_in_other or content_mismatch)
    return {
        "base": base.as_posix(),
        "other": other.as_posix(),
        "compared_files": sorted(base_keys & other_keys),
        "only_in_base": only_in_base,
        "only_in_other": only_in_other,
        "content_mismatch": content_mismatch,
        "identical": identical,
    }


def _resolve_env_folder(raw: str) -> Path:
    path = Path(raw)
    if not path.exists():
        raise ComparatorError(f"la ruta no existe: {raw}")
    if not path.is_dir():
        raise ComparatorError(f"la ruta no es una carpeta: {raw}")
    return path


def _format_text_report(report: dict) -> str:
    lines: list[str] = []
    base = report["base"]
    other = report["other"]
    if report["identical"]:
        n = len(report["compared_files"])
        lines.append(
            f"OK: {n} archivo(s) de Stack idéntico(s) entre {base} y {other} "
            "(los Hierarchy_Files se ignoran)."
        )
        return "\n".join(lines)

    lines.append(f"DIFERENCIAS entre {base} y {other}:")
    for key in report["only_in_base"]:
        lines.append(f"  solo en {base}: {key}")
    for key in report["only_in_other"]:
        lines.append(f"  solo en {other}: {key}")
    for key in report["content_mismatch"]:
        lines.append(f"  contenido distinto (no byte-idéntico): {key}")
    lines.append(
        "Los archivos de Stack deben ser byte-idénticos entre carpetas de "
        "entorno (Requisito 13.1). Mueva los valores que cambian por entorno a "
        "los Hierarchy_Files."
    )
    return "\n".join(lines)


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Compara los archivos de Stack entre dos carpetas "
            "live/contactcenter-<env>, ignorando los Hierarchy_Files."
        )
    )
    parser.add_argument("base", help="carpeta de entorno de referencia (p. ej. live/contactcenter-dev)")
    parser.add_argument("other", help="carpeta de entorno a comparar (p. ej. live/contactcenter-qa)")
    parser.add_argument(
        "--json",
        action="store_true",
        help="emitir el informe en JSON en lugar de texto",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    try:
        base = _resolve_env_folder(args.base)
        other = _resolve_env_folder(args.other)
    except ComparatorError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    report = compare_env_folders(base, other)

    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
    else:
        text = _format_text_report(report)
        stream = sys.stdout if report["identical"] else sys.stderr
        print(text, file=stream)

    return 0 if report["identical"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
