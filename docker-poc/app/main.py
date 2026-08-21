import hashlib
import io
import json
import os
import re
from datetime import datetime, timezone

import trino
from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from minio import Minio

app = FastAPI(title="JSONDoc Lakehouse")
templates = Jinja2Templates(directory="templates")
bucket = os.getenv("MINIO_BUCKET", "jsondocs")
minio = Minio(
    os.getenv("MINIO_ENDPOINT", "minio:9000"),
    access_key=os.environ["MINIO_ACCESS_KEY"],
    secret_key=os.environ["MINIO_SECRET_KEY"],
    secure=False,
)


def trino_cursor():
    return trino.dbapi.connect(
        host=os.getenv("TRINO_HOST", "trino"),
        port=int(os.getenv("TRINO_PORT", "8080")),
        user="jsondoc_app",
        catalog="iceberg",
        schema="jsondoc",
    ).cursor()


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def bootstrap():
    cur = trino_cursor()
    cur.execute("CREATE SCHEMA IF NOT EXISTS iceberg.jsondoc")
    cur.fetchall()
    cur.execute("""CREATE TABLE IF NOT EXISTS iceberg.jsondoc.file_metadata (
        object_key varchar, file_name varchar, content_type varchar, byte_size bigint,
        sha256 varchar, uploaded_at timestamp(6) with time zone, object_uri varchar,
        document_id varchar, document_type varchar
    ) WITH (format='PARQUET')""")
    cur.fetchall()


@app.on_event("startup")
def startup():
    bootstrap()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/", response_class=HTMLResponse)
def home(request: Request):
    cur = trino_cursor()
    cur.execute("SELECT object_key, file_name, content_type, byte_size, sha256, uploaded_at, object_uri, document_id, document_type FROM iceberg.jsondoc.file_metadata ORDER BY uploaded_at DESC")
    rows = cur.fetchall()
    return templates.TemplateResponse("index.html", {"request": request, "rows": rows})


@app.post("/upload")
async def upload(file: UploadFile = File(...)):
    if not file.filename or not file.filename.lower().endswith(".json"):
        raise HTTPException(400, "Only .json files are accepted")
    raw = await file.read()
    try:
        doc = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise HTTPException(400, f"Invalid JSON: {exc.msg}") from exc
    digest = hashlib.sha256(raw).hexdigest()
    safe_name = re.sub(r"[^A-Za-z0-9._-]", "_", file.filename)
    now = datetime.now(timezone.utc)
    key = f"uploads/{now:%Y/%m/%d}/{digest[:12]}-{safe_name}"
    content_type = file.content_type or "application/json"
    minio.put_object(bucket, key, io.BytesIO(raw), len(raw), content_type=content_type)
    public_host = os.getenv("MINIO_PUBLIC_ENDPOINT", "woko.labs.localhost.com:9000")
    uri = f"http://{public_host}/{bucket}/{key}"
    doc_id = str(doc.get("id", "")) if isinstance(doc, dict) else ""
    doc_type = str(doc.get("type", "")) if isinstance(doc, dict) else ""
    cur = trino_cursor()
    values = [key, safe_name, content_type, digest, uri, doc_id, doc_type]
    cur.execute(f"""INSERT INTO iceberg.jsondoc.file_metadata VALUES (
        {sql_literal(values[0])}, {sql_literal(values[1])}, {sql_literal(values[2])}, {len(raw)},
        {sql_literal(values[3])}, from_iso8601_timestamp({sql_literal(now.isoformat())}),
        {sql_literal(values[4])}, {sql_literal(values[5])}, {sql_literal(values[6])})""")
    cur.fetchall()
    return RedirectResponse(url="/", status_code=303)
