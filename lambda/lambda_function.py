import csv
import io
import json
import os
import time
from datetime import datetime, timezone

import boto3

iam = boto3.client("iam")
s3 = boto3.client("s3")
sns = boto3.client("sns")

BUCKET = os.environ["BUCKET"]
TOPIC_ARN = os.environ["TOPIC_ARN"]
MAX_KEY_AGE_DAYS = int(os.environ.get("MAX_KEY_AGE_DAYS", "90"))


def obtener_reporte():
    # El credential report lo genera IAM; hay que esperar a que esté listo
    for _ in range(15):
        estado = iam.generate_credential_report()["State"]
        if estado == "COMPLETE":
            break
        time.sleep(2)
    else:
        raise RuntimeError("El credential report no se generó a tiempo")

    contenido = iam.get_credential_report()["Content"].decode("utf-8")
    return list(csv.DictReader(io.StringIO(contenido)))


def evaluar(filas):
    hallazgos = []
    ahora = datetime.now(timezone.utc)

    for f in filas:
        usuario = f["user"]

        if usuario == "<root_account>":
            if f["mfa_active"] != "true":
                hallazgos.append({"usuario": "root", "problema": "La cuenta root no tiene MFA"})
            for n in (1, 2):
                if f[f"access_key_{n}_active"] == "true":
                    hallazgos.append({"usuario": "root", "problema": f"La cuenta root tiene la access key {n} activa"})
            continue

        if f["password_enabled"] == "true" and f["mfa_active"] != "true":
            hallazgos.append({"usuario": usuario, "problema": "Tiene acceso a la consola sin MFA"})

        for n in (1, 2):
            if f[f"access_key_{n}_active"] == "true":
                rotada = datetime.fromisoformat(f[f"access_key_{n}_last_rotated"])
                dias = (ahora - rotada).days
                if dias > MAX_KEY_AGE_DAYS:
                    hallazgos.append({"usuario": usuario, "problema": f"La access key {n} tiene {dias} días sin rotarse"})

    return hallazgos


def lambda_handler(event, context):
    filas = obtener_reporte()
    hallazgos = evaluar(filas)
    fecha = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    reporte = {
        "fecha": fecha,
        "usuarios_revisados": len(filas),
        "hallazgos": hallazgos,
    }

    s3.put_object(
        Bucket=BUCKET,
        Key=f"reportes/{fecha}.json",
        Body=json.dumps(reporte, indent=2, ensure_ascii=False).encode("utf-8"),
        ContentType="application/json",
    )

    if hallazgos:
        lineas = [f"- {h['usuario']}: {h['problema']}" for h in hallazgos]
        mensaje = f"Se encontraron {len(hallazgos)} hallazgos:\n\n" + "\n".join(lineas)
    else:
        mensaje = "No se encontraron hallazgos. Todo en orden."

    sns.publish(
        TopicArn=TOPIC_ARN,
        Subject=f"Auditoría IAM {fecha}: {len(hallazgos)} hallazgos",
        Message=mensaje,
    )

    return reporte