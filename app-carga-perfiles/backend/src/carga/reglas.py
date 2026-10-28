"""Reglas de validacion y transformacion de la base de socios.

Espejo de src/customerProfilesMapping.ts. El esquema publicado (DynamoDB) decide que
columna del archivo alimenta cada destino; aqui viven las reglas de negocio por destino.
"""

from __future__ import annotations

import csv
import io
import re
from dataclasses import dataclass, field
from datetime import date
from typing import Iterable

# Destino -> nombre del campo en el object type de Customer Profiles (_source.<campo>).
# Debe coincidir con local.campos_object_type en Terraform.
CAMPO_OBJECT_TYPE = {
    "account-number":      "account_number",
    "first-name":          "first_name",
    "mobile-phone":        "mobile_phone",
    "personal-email":      "personal_email",
    "birth-date":          "birth_date",
    "segmento-valor":      "segmento_valor",
    "marca-retener":       "marca_retener",
    "tiene-oferta":        "tiene_oferta",
    "tea":                 "tea",
    "fecha-afiliacion":    "fecha_afiliacion",
    "tipo-producto":       "tipo_producto",
    # Campos confirmados 26-27 de octubre
    "score-oferta":        "score_oferta",
    "linea-credito":       "linea_credito",
    "callcenter-cobranza": "callcenter_cobranza",
    "central-cobranza":    "central_cobranza",
    "refinanciado":        "refinanciado",
}

PRODUCTOS = {"free", "hiraoka", "club", "miles", "special edition", "carte blanche"}
RE_DNI = re.compile(r"^\d{8}$")
RE_TELEFONO = re.compile(r"^51\d{9}$")
RE_CORREO = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$")
RE_FECHA = re.compile(r"^\d{4}-\d{2}-\d{2}$")
# Vacios que no son error, sino advertencia (el perfil se escribe sin el dato).
ADVERTENCIA_SI_VACIO = {
    "mobile-phone":   "Campo vacío: el socio no recibirá llamada de vuelta",
    "segmento-valor": "Campo vacío: se enrutará al grupo general",
    "score-oferta":   "Campo vacío: no se puede determinar el canal de llamada de venta",
}

MAX_HALLAZGOS_DETALLE = 5000
NOMBRE_FECHA = {"fecha-afiliacion": "fecha_afiliacion", "birth-date": "fecha_nacimiento"}


@dataclass
class Hallazgo:
    linea: int
    dni: str
    columna: str
    motivo: str
    tipo: str  # "rechazo" | "advertencia"


@dataclass
class ResultadoValidacion:
    filas_procesadas: int = 0
    validas: list[dict] = field(default_factory=list)
    hallazgos: list[Hallazgo] = field(default_factory=list)
    filas_rechazadas: int = 0
    advertencias: int = 0
    error_archivo: str | None = None


def _normalizar(nombre: str) -> str:
    import unicodedata

    s = unicodedata.normalize("NFD", nombre)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9]", "", s.lower())


def decodificar(contenido: bytes) -> str:
    """UTF-8 con o sin BOM; si falla, Latin-1 (Excel en español)."""
    try:
        return contenido.decode("utf-8-sig")
    except UnicodeDecodeError:
        return contenido.decode("latin-1")


def _validar_valor(destino: str, valor: str, fila: dict[str, str]) -> tuple[str | None, str | None, str]:
    """Devuelve (rechazo, advertencia, valor_normalizado)."""
    if destino == "account-number":
        return (None if RE_DNI.match(valor) else "DNI con longitud invalida", None, valor)
    if destino in ("mobile-phone", "phone-number"):
        digitos = re.sub(r"[\s-]", "", valor).lstrip("+")
        if not RE_TELEFONO.match(digitos):
            return ("Telefono con formato invalido", None, valor)
        return (None, None, f"+{digitos}")
    if destino == "personal-email":
        return (None if RE_CORREO.match(valor) else "Correo con formato invalido", None, valor.lower())
    if destino == "segmento-valor":
        return (None if valor in ("1", "2", "3") else "SEGMENTO_VALOR debe ser 1, 2 o 3", None, valor)
    if destino == "marca-retener":
        return (None if valor in ("1", "2") else "MARCA_RETENER debe ser 1 o 2", None, valor)
    if destino == "tiene-oferta":
        v = valor.upper()
        if v in ("S", "SI", "SÍ"):
            return (None, None, "S")
        if v in ("N", "NO"):
            return (None, None, "N")
        return ("tiene_oferta debe ser S o N", None, valor)
    if destino == "tea":
        try:
            numero = float(valor.replace(",", "."))
        except ValueError:
            return ("tea no es un numero", None, valor)
        if not 0 <= numero <= 200:
            return ("tea fuera del rango permitido", None, valor)
        return (None, None, f"{numero:g}")
    if destino in ("fecha-afiliacion", "birth-date"):
        if not RE_FECHA.match(valor):
            return (f"{NOMBRE_FECHA[destino]} con formato invalido", None, valor)
        try:
            f = date.fromisoformat(valor)
        except ValueError:
            return (f"{NOMBRE_FECHA[destino]} con formato invalido", None, valor)
        if f > date.today():
            return (f"{NOMBRE_FECHA[destino]} no puede ser futura", None, valor)
        return (None, None, valor)
    if destino == "tipo-producto":
        if valor.lower() not in PRODUCTOS:
            return ("tipo_producto no permitido", None, valor)
        return (None, None, valor)
    if destino == "score-oferta":
        if valor.upper() not in ("A", "B", "C", "D", "E"):
            return ("score_oferta debe ser A, B, C, D o E", None, valor)
        return (None, None, valor.upper())
    if destino == "refinanciado":
        v = valor.upper()
        if v in ("S", "SI", "SÍ"):
            return (None, None, "S")
        if v in ("N", "NO"):
            return (None, None, "N")
        return ("refinanciado debe ser S o N", None, valor)
    # Campos de texto libre sin validación adicional (linea-credito,
    # callcenter-cobranza, central-cobranza): se guardan tal cual.
    return (None, None, valor)


EXCEL_EPOCH = date(1899, 12, 30)
RE_SERIAL = re.compile(r"^\d{4,6}(\.\d+)?$")


def _normalizar_excel(destino: str, valor: str) -> str:
    """Excel guarda el DNI como numero (pierde ceros a la izquierda) y las fechas como serial."""
    # Solo 6 o 7 digitos: ceros iniciales perdidos. Un DNI de 4 digitos es un error real y debe rechazarse.
    if destino == "account-number" and valor.isdigit() and len(valor) in (6, 7):
        return valor.zfill(8)
    if destino in ("fecha-afiliacion", "birth-date") and RE_SERIAL.match(valor):
        from datetime import timedelta

        return (EXCEL_EPOCH + timedelta(days=int(float(valor)))).isoformat()
    return valor


def validar_csv(texto: str, esquema: dict) -> ResultadoValidacion:
    primera = texto.split("\n", 1)[0]
    delimitador = ";" if primera.count(";") > primera.count(",") else ","
    return validar_filas(csv.reader(io.StringIO(texto), delimiter=delimitador), esquema, excel=False)


def validar_xlsx(contenido: bytes, esquema: dict) -> ResultadoValidacion:
    from .xlsx import ErrorXlsx, leer_filas

    try:
        return validar_filas(leer_filas(contenido), esquema, excel=True)
    except ErrorXlsx as e:
        return ResultadoValidacion(error_archivo=str(e))


def validar_archivo(nombre: str, contenido: bytes, esquema: dict) -> ResultadoValidacion:
    if nombre.lower().endswith(".xlsx"):
        return validar_xlsx(contenido, esquema)
    return validar_csv(decodificar(contenido), esquema)


def validar_filas(lector: Iterable[list[str]], esquema: dict, excel: bool) -> ResultadoValidacion:
    res = ResultadoValidacion()
    lector = iter(lector)
    try:
        cabecera = [c.strip() for c in next(lector)]
    except StopIteration:
        res.error_archivo = "El archivo está vacío."
        return res

    indice = {_normalizar(c): i for i, c in enumerate(cabecera)}
    campos = esquema["fields"]
    # destino -> (posicion en el archivo, campo del esquema)
    columnas: dict[str, tuple[int, dict]] = {}
    faltantes = []
    for campo in campos:
        pos = indice.get(_normalizar(campo["sourceColumn"]))
        if pos is None:
            if campo.get("required"):
                faltantes.append(campo["sourceColumn"])
            continue
        if campo["destinationId"] not in CAMPO_OBJECT_TYPE:
            continue
        columnas[campo["destinationId"]] = (pos, campo)
    if faltantes:
        res.error_archivo = "Faltan columnas obligatorias: " + ", ".join(faltantes)
        return res
    if "account-number" not in columnas:
        res.error_archivo = "El esquema no tiene una columna mapeada al identificador (AccountNumber)."
        return res

    vistos: set[str] = set()
    for n, valores in enumerate(lector, start=2):
        if not any(v.strip() for v in valores):
            continue
        res.filas_procesadas += 1
        crudo = {d: (valores[p].strip() if p < len(valores) else "") for d, (p, _) in columnas.items()}
        if excel:
            crudo = {d: _normalizar_excel(d, v) for d, v in crudo.items()}
        dni = crudo["account-number"]
        rechazos: list[Hallazgo] = []
        advertencias: list[Hallazgo] = []
        objeto: dict[str, str] = {}
        for destino, (_, campo) in columnas.items():
            valor = crudo[destino]
            col = campo["sourceColumn"]
            if not valor:
                if destino in ADVERTENCIA_SI_VACIO:
                    advertencias.append(Hallazgo(n, dni, col, ADVERTENCIA_SI_VACIO[destino], "advertencia"))
                elif campo.get("required"):
                    rechazos.append(Hallazgo(n, dni, col, f"{col} es obligatorio", "rechazo"))
                continue
            rechazo, advertencia, normalizado = _validar_valor(destino, valor, crudo)
            if rechazo:
                rechazos.append(Hallazgo(n, dni, col, rechazo, "rechazo"))
            else:
                objeto[CAMPO_OBJECT_TYPE[destino]] = normalizado
            if advertencia:
                advertencias.append(Hallazgo(n, dni, col, advertencia, "advertencia"))
        if not crudo.get("tea") and objeto.get("tiene_oferta") == "S" and "tea" in columnas:
            advertencias.append(
                Hallazgo(n, dni, columnas["tea"][1]["sourceColumn"],
                         "Campo vacio con tiene_oferta en S: el agente no podra simular", "advertencia")
            )
        if not rechazos and dni in vistos:
            rechazos.append(Hallazgo(n, dni, columnas["account-number"][1]["sourceColumn"],
                                     "DNI duplicado en el archivo", "rechazo"))
        if rechazos:
            res.filas_rechazadas += 1
            res.hallazgos.extend(rechazos)
        else:
            vistos.add(dni)
            res.validas.append(objeto)
        res.advertencias += len(advertencias)
        res.hallazgos.extend(advertencias)

    if res.filas_procesadas == 0:
        res.error_archivo = "El archivo no tiene filas de datos."
    return res


def hallazgos_a_csv(hallazgos: Iterable[Hallazgo]) -> str:
    salida = io.StringIO()
    w = csv.writer(salida)
    w.writerow(["linea", "dni", "columna", "tipo", "motivo"])
    for h in hallazgos:
        w.writerow([h.linea, h.dni, h.columna, h.tipo, h.motivo])
    # BOM para que Excel en Windows abra bien las tildes.
    return "\ufeff" + salida.getvalue()
