"""Lector minimo de .xlsx con la biblioteca estandar (zip + XML en streaming).

Lee la primera hoja y devuelve cada fila como lista de textos. Evita empaquetar openpyxl
en la Lambda y no carga la hoja completa en memoria (iterparse).
"""

from __future__ import annotations

import io
import re
import zipfile
from decimal import Decimal, InvalidOperation
from typing import Iterator
from xml.etree.ElementTree import iterparse

NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
NS_REL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
RE_COL = re.compile(r"^([A-Z]+)")


class ErrorXlsx(ValueError):
    pass


def _indice_columna(ref: str) -> int:
    letras = RE_COL.match(ref).group(1)
    n = 0
    for c in letras:
        n = n * 26 + (ord(c) - 64)
    return n - 1


def _texto_numero(valor: str) -> str:
    """Excel guarda 45678901 como '45678901' o '4.5678901E7'; se devuelve sin decimales si es entero."""
    try:
        d = Decimal(valor)
    except InvalidOperation:
        return valor
    if d == d.to_integral_value():
        return str(d.quantize(Decimal(1)))
    return format(d.normalize(), "f")


def _compartidos(z: zipfile.ZipFile) -> list[str]:
    if "xl/sharedStrings.xml" not in z.namelist():
        return []
    salida: list[str] = []
    with z.open("xl/sharedStrings.xml") as f:
        for _, el in iterparse(f):
            if el.tag == f"{NS}si":
                salida.append("".join(t.text or "" for t in el.iter(f"{NS}t")))
                el.clear()
    return salida


def _primera_hoja(z: zipfile.ZipFile) -> str:
    """Resuelve la ruta de la primera hoja segun workbook.xml (no siempre es sheet1.xml)."""
    try:
        from xml.etree.ElementTree import fromstring

        libro = fromstring(z.read("xl/workbook.xml"))
        hoja = libro.find(f"{NS}sheets/{NS}sheet")
        rid = hoja.get(f"{NS_REL}id")
        rels = fromstring(z.read("xl/_rels/workbook.xml.rels"))
        for r in rels:
            if r.get("Id") == rid:
                destino = r.get("Target").lstrip("/")
                return destino if destino.startswith("xl/") else f"xl/{destino}"
    except (KeyError, AttributeError):
        pass
    return "xl/worksheets/sheet1.xml"


def leer_filas(contenido: bytes) -> Iterator[list[str]]:
    try:
        z = zipfile.ZipFile(io.BytesIO(contenido))
    except zipfile.BadZipFile as e:
        raise ErrorXlsx("El archivo no es un Excel .xlsx válido.") from e
    compartidos = _compartidos(z)
    ruta = _primera_hoja(z)
    if ruta not in z.namelist():
        raise ErrorXlsx("El Excel no tiene hojas.")

    with z.open(ruta) as f:
        for _, el in iterparse(f):
            if el.tag != f"{NS}row":
                continue
            fila: list[str] = []
            for c in el.iter(f"{NS}c"):
                pos = _indice_columna(c.get("r", "A1")) if c.get("r") else len(fila)
                tipo = c.get("t", "n")
                if tipo == "inlineStr":
                    valor = "".join(t.text or "" for t in c.iter(f"{NS}t"))
                else:
                    v = c.find(f"{NS}v")
                    crudo = v.text if v is not None and v.text is not None else ""
                    if tipo == "s":
                        valor = compartidos[int(crudo)] if crudo else ""
                    elif tipo == "b":
                        valor = "SI" if crudo == "1" else "NO"
                    elif tipo in ("str", "e"):
                        valor = crudo
                    else:
                        valor = _texto_numero(crudo) if crudo else ""
                while len(fila) < pos:
                    fila.append("")
                fila.append(valor)
            el.clear()
            yield fila
