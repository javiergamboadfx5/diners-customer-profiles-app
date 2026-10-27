"""Procesos asincronos: validar el archivo, encolar filas validas y escribir en Customer Profiles."""

from __future__ import annotations

import json
import urllib.parse

from botocore.exceptions import ClientError

from . import comun, reglas
from .comun import a_json, log

FILAS_POR_MENSAJE = 25
ERRORES_REINTENTABLES = {"ThrottlingException", "TooManyRequestsException", "InternalServerException",
                         "ServiceUnavailableException"}


def _poner(clave: str, cuerpo: str, tipo: str) -> None:
    comun.s3.put_object(Bucket=comun.BUCKET, Key=clave, Body=cuerpo.encode("utf-8"), ContentType=tipo)


# ---------- 1. Validacion (evento de S3 al subir original.csv) ----------

def validador(evento, _contexto):
    for registro in evento.get("Records", []):
        clave = urllib.parse.unquote_plus(registro["s3"]["object"]["key"])
        partes = clave.split("/")
        if len(partes) != 3 or partes[0] != "cargas" or partes[2] not in ("original.csv", "original.xlsx"):
            continue
        _validar_carga(partes[1], clave)


def _validar_carga(carga_id: str, clave: str) -> None:
    try:
        comun.actualizar_carga(carga_id, condicion_estado="subiendo", estado="validando")
    except comun.TABLA.meta.client.exceptions.ConditionalCheckFailedException:
        log.warning("carga %s no esta en 'subiendo'; se ignora el archivo", carga_id)
        return
    try:
        esquema = comun.esquema_actual()
        contenido = comun.s3.get_object(Bucket=comun.BUCKET, Key=clave)["Body"].read()
        res = reglas.validar_archivo(clave, contenido, esquema)
        base = comun.prefijo(carga_id)

        _poner(f"{base}/reporte.csv", reglas.hallazgos_a_csv(res.hallazgos), "text/csv; charset=utf-8")
        detalle = [
            {"id": f"h-{i}", "linea": h.linea, "dni": h.dni, "columna": h.columna, "motivo": h.motivo, "tipo": h.tipo}
            for i, h in enumerate(res.hallazgos[: reglas.MAX_HALLAZGOS_DETALLE], start=1)
        ]
        _poner(f"{base}/hallazgos.json",
               a_json({"total": len(res.hallazgos), "hallazgos": detalle}), "application/json")
        if res.validas:
            _poner(f"{base}/validas.jsonl", "\n".join(json.dumps(f, ensure_ascii=False) for f in res.validas),
                   "application/x-ndjson")

        rechazada = bool(res.error_archivo) or not res.validas
        comun.actualizar_carga(
            carga_id,
            estado="rechazada" if rechazada else "validada",
            filasProcesadas=res.filas_procesadas,
            filasValidas=len(res.validas),
            filasRechazadas=res.filas_rechazadas,
            advertencias=res.advertencias,
            esquemaVersion=int(esquema["version"]),
            error=res.error_archivo or ("Ninguna fila pasó la validación." if not res.validas else ""),
            **({"finalizadaEn": comun.ahora()} if rechazada else {}),
        )
        if rechazada:
            comun.liberar_lock(carga_id)
        log.info("carga %s validada: %s validas, %s rechazadas", carga_id, len(res.validas), res.filas_rechazadas)
    except Exception as e:  # noqa: BLE001
        log.exception("fallo la validacion de %s", carga_id)
        comun.actualizar_carga(carga_id, estado="fallida", error=f"Error al validar: {type(e).__name__}",
                               finalizadaEn=comun.ahora())
        comun.liberar_lock(carga_id)


# ---------- 2. Encolado (invocado por la API al confirmar) ----------

def encolador(evento, _contexto):
    carga_id = evento["cargaId"]
    try:
        cuerpo = comun.s3.get_object(Bucket=comun.BUCKET, Key=f"{comun.prefijo(carga_id)}/validas.jsonl")["Body"]
        filas = [json.loads(linea) for linea in cuerpo.read().decode("utf-8").splitlines() if linea]
        mensajes = [
            {"Id": str(i), "MessageBody": a_json({"cargaId": carga_id, "filas": filas[j: j + FILAS_POR_MENSAJE]})}
            for i, j in enumerate(range(0, len(filas), FILAS_POR_MENSAJE))
        ]
        for k in range(0, len(mensajes), 10):
            lote = [{**m, "Id": str(n)} for n, m in enumerate(mensajes[k: k + 10])]
            r = comun.sqs.send_message_batch(QueueUrl=comun.COLA, Entries=lote)
            if r.get("Failed"):
                raise RuntimeError(f"SQS rechazo {len(r['Failed'])} mensajes")
        log.info("carga %s: %s filas en %s mensajes", carga_id, len(filas), len(mensajes))
    except Exception as e:  # noqa: BLE001
        log.exception("fallo el encolado de %s", carga_id)
        comun.actualizar_carga(carga_id, estado="fallida", error=f"Error al encolar: {type(e).__name__}",
                               finalizadaEn=comun.ahora())
        comun.liberar_lock(carga_id)


# ---------- 3. Escritura (consumidor de SQS) ----------

def escritor(evento, _contexto):
    fallidos = []
    estados: dict[str, str] = {}
    for registro in evento.get("Records", []):
        try:
            _escribir_mensaje(json.loads(registro["body"]), estados)
        except Exception:  # noqa: BLE001
            log.exception("mensaje %s se reintentara", registro.get("messageId"))
            fallidos.append({"itemIdentifier": registro["messageId"]})
    return {"batchItemFailures": fallidos}


def _escribir_mensaje(mensaje: dict, estados: dict[str, str]) -> None:
    carga_id = mensaje["cargaId"]
    if carga_id not in estados:
        estados[carga_id] = (comun.obtener_carga(carga_id) or {}).get("estado", "")
    if estados[carga_id] != "escribiendo":
        return  # cancelada o terminada: se descarta sin escribir

    ok = malas = 0
    ultimo_error = ""
    for fila in mensaje["filas"]:
        try:
            comun.profiles.put_profile_object(
                DomainName=comun.DOMINIO, ObjectTypeName=comun.OBJECT_TYPE, Object=json.dumps(fila)
            )
            ok += 1
        except ClientError as e:
            codigo = e.response.get("Error", {}).get("Code", "")
            if codigo in ERRORES_REINTENTABLES:
                raise  # el mensaje completo vuelve a la cola; PutProfileObject es idempotente por DNI
            log.warning("fila DNI %s rechazada por Customer Profiles: %s %s", fila.get("account_number"), codigo,
                        e.response.get("Error", {}).get("Message", ""))
            ultimo_error = codigo or "Desconocido"
            malas += 1

    # Contadores una sola vez por mensaje, despues de procesarlo entero.
    expresion = "ADD filasEscritas :ok, fallidasEscritura :m"
    valores: dict = {":ok": ok, ":m": malas}
    if ultimo_error:
        expresion += " SET errorEscritura = :e"
        valores[":e"] = ultimo_error
    r = comun.TABLA.update_item(
        Key=comun.clave_carga(carga_id),
        UpdateExpression=expresion,
        ExpressionAttributeValues=valores,
        ReturnValues="ALL_NEW",
    )["Attributes"]
    if int(r["filasEscritas"]) + int(r["fallidasEscritura"]) >= int(r["filasValidas"]):
        _finalizar(carga_id, int(r["filasEscritas"]), int(r["fallidasEscritura"]), r.get("errorEscritura", ""))


def explicar_error_escritura(codigo: str, fallidas: int, escritas: int) -> str:
    """Mensaje para el usuario: que paso, a cuantos perfiles afecto y que hacer."""
    alcance = (f"No se escribió ninguno de los {fallidas:,} perfiles válidos." if escritas == 0
               else f"Se escribieron {escritas:,} perfiles; {fallidas:,} no se pudieron escribir.").replace(",", ".")
    causas = {
        "AccessDeniedException": "la aplicación no tiene permiso para escribir en Customer Profiles. "
                                 "Un administrador debe revisar el rol de la aplicación y las políticas de la cuenta de AWS.",
        "ResourceNotFoundException": "no existe el dominio o el tipo de objeto de Customer Profiles configurado. "
                                     "Un administrador debe revisar la configuración del despliegue.",
        "BadRequestException": "Customer Profiles rechazó los datos por formato. "
                               "Contacta al administrador con el código de carga.",
        "ValidationException": "Customer Profiles rechazó los datos por formato. "
                               "Contacta al administrador con el código de carga.",
    }
    causa = causas.get(codigo, f"Customer Profiles respondió con el error {codigo}. Contacta al administrador.")
    return f"{alcance} Motivo: {causa} El archivo validado no se modificó; puedes volver a cargarlo cuando se resuelva."


def _finalizar(carga_id: str, escritas: int, fallidas: int, codigo_error: str = "") -> None:
    estado = "completada" if fallidas == 0 else ("fallida" if escritas == 0 else "parcial")
    extra = {"error": explicar_error_escritura(codigo_error, fallidas, escritas)} if fallidas else {}
    try:
        comun.actualizar_carga(carga_id, condicion_estado="escribiendo", estado=estado, finalizadaEn=comun.ahora(),
                               **extra)
    except comun.TABLA.meta.client.exceptions.ConditionalCheckFailedException:
        return
    comun.liberar_lock(carga_id)
    log.info("carga %s finalizada: %s (%s escritas, %s fallidas)", carga_id, estado, escritas, fallidas)
