"""Utilidades compartidas por las funciones de la app de carga."""

from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone
from decimal import Decimal

import boto3
from botocore.config import Config

log = logging.getLogger()
log.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

_cfg = Config(retries={"max_attempts": 10, "mode": "adaptive"})
# SigV4 y endpoint regional: requeridos para URLs prefirmadas sobre objetos cifrados con KMS.
s3 = boto3.client("s3", config=_cfg.merge(Config(signature_version="s3v4", s3={"addressing_style": "virtual"})),
                  endpoint_url=f"https://s3.{os.environ.get('AWS_REGION', 'us-east-1')}.amazonaws.com")
ddb = boto3.resource("dynamodb", config=_cfg)
sqs = boto3.client("sqs", config=_cfg)
lambda_ = boto3.client("lambda", config=_cfg)
profiles = boto3.client("customer-profiles", config=_cfg)

TABLA = ddb.Table(os.environ["TABLA"])
BUCKET = os.environ["BUCKET_CARGAS"]
COLA = os.environ.get("COLA_ESCRITURA", "")
DOMINIO = os.environ.get("DOMINIO_PERFILES", "")
OBJECT_TYPE = os.environ.get("OBJECT_TYPE", "")
FUNCION_ENCOLADOR = os.environ.get("FUNCION_ENCOLADOR", "")

# Estados del backend. El frontend los traduce a sus fases.
EN_CURSO = {"subiendo", "validando", "validada", "escribiendo"}
FINALES = {"completada", "parcial", "rechazada", "fallida", "cancelada"}

ESQUEMA_PK = "ESQUEMA"
LOCK_PK = "LOCK"


def ahora() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def clave_carga(carga_id: str) -> dict:
    return {"pk": f"CARGA#{carga_id}", "sk": "META"}


def prefijo(carga_id: str) -> str:
    return f"cargas/{carga_id}"


def _json_default(o):
    if isinstance(o, Decimal):
        return int(o) if o == o.to_integral_value() else float(o)
    raise TypeError(type(o))


def a_json(obj) -> str:
    return json.dumps(obj, default=_json_default, ensure_ascii=False)


def obtener_carga(carga_id: str) -> dict | None:
    return TABLA.get_item(Key=clave_carga(carga_id)).get("Item")


def actualizar_carga(carga_id: str, condicion_estado: str | None = None, **campos) -> dict:
    nombres = {f"#{k}": k for k in campos}
    valores = {f":{k}": v for k, v in campos.items()}
    args = {
        "Key": clave_carga(carga_id),
        "UpdateExpression": "SET " + ", ".join(f"#{k} = :{k}" for k in campos),
        "ExpressionAttributeNames": nombres,
        "ExpressionAttributeValues": valores,
        "ReturnValues": "ALL_NEW",
    }
    if condicion_estado:
        args["ConditionExpression"] = "#estado_actual = :estado_esperado"
        nombres["#estado_actual"] = "estado"
        valores[":estado_esperado"] = condicion_estado
    return TABLA.update_item(**args)["Attributes"]


def liberar_lock(carga_id: str) -> None:
    try:
        TABLA.delete_item(
            Key={"pk": LOCK_PK, "sk": "LOCK"},
            ConditionExpression="cargaId = :c",
            ExpressionAttributeValues={":c": carga_id},
        )
    except ddb.meta.client.exceptions.ConditionalCheckFailedException:
        pass


def esquema_actual() -> dict | None:
    item = TABLA.get_item(Key={"pk": ESQUEMA_PK, "sk": "ACTUAL"}).get("Item")
    return json.loads(item["esquema"]) if item else None
