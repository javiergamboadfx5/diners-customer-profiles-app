"""API HTTP de la app de carga (API Gateway HTTP API, payload v2, autorizador JWT)."""

from __future__ import annotations

import json
import os
import re
import secrets
import time
from datetime import datetime, timezone

from boto3.dynamodb.conditions import Key

from . import comun
from .comun import TABLA, a_json, log

MAX_BYTES = int(os.environ.get("MAX_BYTES", str(100 * 1024 * 1024)))
GRUPOS_CARGA = {g for g in os.environ.get("GRUPOS_CARGA", "").split(",") if g}
GRUPOS_ADMIN = {g for g in os.environ.get("GRUPOS_ADMIN", "").split(",") if g}
LOCK_HORAS = 6
RE_ARCHIVO = re.compile(r"^[\w .()-]{1,120}\.csv$", re.IGNORECASE)


class ErrorHttp(Exception):
    def __init__(self, status: int, mensaje: str):
        super().__init__(mensaje)
        self.status = status
        self.mensaje = mensaje


def _resp(status: int, cuerpo) -> dict:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store"},
        "body": a_json(cuerpo),
    }


# ---------- identidad y autorizacion ----------

def _claims(evento: dict) -> dict:
    return evento.get("requestContext", {}).get("authorizer", {}).get("jwt", {}).get("claims", {}) or {}


def _grupos(claims: dict) -> set[str]:
    crudo = claims.get("groups") or claims.get("cognito:groups") or ""
    if isinstance(crudo, list):
        return set(crudo)
    # HTTP API serializa los arreglos como "[a b c]".
    return {g for g in re.split(r"[\s,\[\]\"]+", str(crudo)) if g}


def _usuario(claims: dict) -> str:
    return str(claims.get("preferred_username") or claims.get("email") or claims.get("upn")
               or claims.get("name") or claims.get("sub") or "desconocido")


def _autorizar(claims: dict, grupos_requeridos: set[str]) -> None:
    if grupos_requeridos and not (_grupos(claims) & grupos_requeridos):
        raise ErrorHttp(403, "Tu usuario no tiene permiso para esta acción.")


# ---------- handlers ----------

def _listar(_evento, _claims):
    r = TABLA.query(IndexName="gsi1", KeyConditionExpression=Key("gsi1pk").eq("CARGAS"),
                    ScanIndexForward=False, Limit=50)
    return 200, {"cargas": [_publica(i) for i in r.get("Items", [])]}


def _publica(item: dict) -> dict:
    return {k: v for k, v in item.items() if k not in ("pk", "sk", "gsi1pk", "gsi1sk")}


def _crear(evento, claims):
    _autorizar(claims, GRUPOS_CARGA)
    cuerpo = json.loads(evento.get("body") or "{}")
    archivo = str(cuerpo.get("archivo", "")).strip()
    tamano = int(cuerpo.get("tamanoBytes") or 0)
    if not RE_ARCHIVO.match(archivo):
        raise ErrorHttp(400, "El archivo debe ser .csv y tener un nombre simple.")
    if not 0 < tamano <= MAX_BYTES:
        raise ErrorHttp(400, f"El archivo debe pesar entre 1 byte y {MAX_BYTES // (1024 * 1024)} MB.")
    if not comun.esquema_actual():
        raise ErrorHttp(409, "No hay un esquema publicado.")

    fecha = datetime.now(timezone.utc)
    carga_id = f"CRG-{fecha:%Y%m%d-%H%M%S}-{secrets.token_hex(2)}"
    ahora_ts = int(time.time())
    try:
        TABLA.put_item(
            Item={"pk": comun.LOCK_PK, "sk": "LOCK", "cargaId": carga_id, "expira": ahora_ts + LOCK_HORAS * 3600},
            ConditionExpression="attribute_not_exists(pk) OR expira < :t",
            ExpressionAttributeValues={":t": ahora_ts},
        )
    except TABLA.meta.client.exceptions.ConditionalCheckFailedException:
        raise ErrorHttp(409, "Ya hay una carga en curso. Espera a que termine o cancélala.")

    item = {
        **comun.clave_carga(carga_id),
        "gsi1pk": "CARGAS",
        "gsi1sk": fecha.isoformat(timespec="seconds"),
        "id": carga_id,
        "fecha": fecha.isoformat(timespec="seconds"),
        "usuario": _usuario(claims),
        "archivo": archivo,
        "tamanoBytes": tamano,
        "estado": "subiendo",
        "filasProcesadas": 0,
        "filasValidas": 0,
        "filasEscritas": 0,
        "fallidasEscritura": 0,
        "filasRechazadas": 0,
        "advertencias": 0,
    }
    TABLA.put_item(Item=item)
    subida = comun.s3.generate_presigned_post(
        Bucket=comun.BUCKET,
        Key=f"{comun.prefijo(carga_id)}/original.csv",
        Conditions=[["content-length-range", 1, MAX_BYTES]],
        ExpiresIn=900,
    )
    log.info("carga creada %s por %s", carga_id, item["usuario"])
    return 201, {"carga": _publica(item), "subida": subida}


def _carga_o_404(carga_id: str) -> dict:
    item = comun.obtener_carga(carga_id)
    if not item:
        raise ErrorHttp(404, "La carga no existe.")
    return item


def _obtener(_evento, _claims, carga_id):
    return 200, {"carga": _publica(_carga_o_404(carga_id))}


def _confirmar(_evento, claims, carga_id):
    _autorizar(claims, GRUPOS_CARGA)
    _carga_o_404(carga_id)
    try:
        item = comun.actualizar_carga(carga_id, condicion_estado="validada", estado="escribiendo",
                                      confirmadaPor=_usuario(claims), confirmadaEn=comun.ahora())
    except TABLA.meta.client.exceptions.ConditionalCheckFailedException:
        raise ErrorHttp(409, "La carga no está esperando confirmación.")
    comun.lambda_.invoke(FunctionName=comun.FUNCION_ENCOLADOR, InvocationType="Event",
                         Payload=a_json({"cargaId": carga_id}).encode())
    return 200, {"carga": _publica(item)}


def _cancelar(_evento, claims, carga_id):
    _autorizar(claims, GRUPOS_CARGA)
    item = _carga_o_404(carga_id)
    if item["estado"] not in comun.EN_CURSO:
        raise ErrorHttp(409, "La carga ya terminó.")
    item = comun.actualizar_carga(carga_id, condicion_estado=item["estado"], estado="cancelada",
                                  canceladaPor=_usuario(claims), finalizadaEn=comun.ahora())
    comun.liberar_lock(carga_id)
    return 200, {"carga": _publica(item)}


def _descarga(nombre: str, tipo: str):
    def handler(_evento, _claims, carga_id):
        _carga_o_404(carga_id)
        clave = f"{comun.prefijo(carga_id)}/{nombre}"
        try:
            comun.s3.head_object(Bucket=comun.BUCKET, Key=clave)
        except comun.s3.exceptions.ClientError:
            raise ErrorHttp(404, "El reporte aún no está disponible.")
        url = comun.s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": comun.BUCKET, "Key": clave, "ResponseContentType": tipo,
                    "ResponseContentDisposition": f'attachment; filename="{carga_id}-{nombre}"'},
            ExpiresIn=300,
        )
        return 200, {"url": url}
    return handler


def _esquema(_evento, _claims):
    esquema = comun.esquema_actual()
    if not esquema:
        raise ErrorHttp(404, "No hay un esquema publicado.")
    return 200, {"esquema": esquema}


def _publicar_esquema(evento, claims):
    _autorizar(claims, GRUPOS_ADMIN or GRUPOS_CARGA)
    nuevo = json.loads(evento.get("body") or "{}").get("esquema") or {}
    actual = comun.esquema_actual() or {"version": 0}
    campos = nuevo.get("fields") or []
    if int(nuevo.get("version", 0)) != int(actual["version"]) + 1:
        raise ErrorHttp(409, "Otra persona publicó una versión. Recarga la página.")
    if not campos or any(not re.match(r"^[a-zA-Z0-9_.-]{1,64}$", str(c.get("sourceColumn", ""))) for c in campos):
        raise ErrorHttp(400, "Hay columnas sin nombre o con caracteres inválidos.")
    if sum(1 for c in campos if c.get("identifier") == "PROFILE_UNIQUE") != 1:
        raise ErrorHttp(400, "Define exactamente un identificador principal.")
    if not any(c.get("destinationId") == "account-number" for c in campos):
        raise ErrorHttp(400, "Una columna debe mapearse a AccountNumber (DNI).")

    nuevo["updatedAt"] = comun.ahora()
    nuevo["updatedBy"] = _usuario(claims)
    serial = a_json(nuevo)
    try:
        TABLA.put_item(
            Item={"pk": comun.ESQUEMA_PK, "sk": "ACTUAL", "version": nuevo["version"], "esquema": serial},
            ConditionExpression="attribute_not_exists(pk) OR version = :v",
            ExpressionAttributeValues={":v": actual["version"]},
        )
    except TABLA.meta.client.exceptions.ConditionalCheckFailedException:
        raise ErrorHttp(409, "Otra persona publicó una versión. Recarga la página.")
    TABLA.put_item(Item={"pk": comun.ESQUEMA_PK, "sk": f"V#{int(nuevo['version']):04d}", "esquema": serial})
    return 200, {"esquema": nuevo}


RUTAS_FIJAS = {
    ("GET", "/api/cargas"): _listar,
    ("POST", "/api/cargas"): _crear,
    ("GET", "/api/esquema"): _esquema,
    ("PUT", "/api/esquema"): _publicar_esquema,
}
RUTAS_CARGA = {
    ("GET", ""): _obtener,
    ("POST", "/confirmar"): _confirmar,
    ("POST", "/cancelar"): _cancelar,
    ("GET", "/reporte"): _descarga("reporte.csv", "text/csv; charset=utf-8"),
    ("GET", "/hallazgos"): _descarga("hallazgos.json", "application/json"),
}
RE_CARGA = re.compile(r"^/api/cargas/(CRG-[0-9]{8}-[0-9]{6}-[0-9a-f]{4})(/[a-z]+)?$")


def handler(evento, _contexto):
    metodo = evento.get("requestContext", {}).get("http", {}).get("method", "")
    ruta = evento.get("rawPath", "")
    claims = _claims(evento)
    try:
        if (metodo, ruta) in RUTAS_FIJAS:
            status, cuerpo = RUTAS_FIJAS[(metodo, ruta)](evento, claims)
        else:
            m = RE_CARGA.match(ruta)
            fn = RUTAS_CARGA.get((metodo, (m.group(2) or "") if m else None)) if m else None
            if not fn:
                raise ErrorHttp(404, "Ruta no encontrada.")
            status, cuerpo = fn(evento, claims, m.group(1))
        return _resp(status, cuerpo)
    except ErrorHttp as e:
        return _resp(e.status, {"mensaje": e.mensaje})
    except (ValueError, json.JSONDecodeError):
        return _resp(400, {"mensaje": "Solicitud inválida."})
    except Exception:  # noqa: BLE001
        log.exception("error no controlado en %s %s", metodo, ruta)
        return _resp(500, {"mensaje": "Error interno. Intenta de nuevo."})
