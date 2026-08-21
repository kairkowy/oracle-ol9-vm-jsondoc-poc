import hashlib
import io
import json
import os
import re
from datetime import datetime, timezone

import pymysql
from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from minio import Minio

app = FastAPI(title="JSONDoc Lakehouse")
templates = Jinja2Templates(directory=os.path.join(os.path.dirname(__file__), "templates"))
bucket = os.getenv("MINIO_BUCKET", "jsondocs")
minio = Minio(os.environ["MINIO_ENDPOINT"], access_key=os.environ["MINIO_ACCESS_KEY"],
              secret_key=os.environ["MINIO_SECRET_KEY"], secure=False)


def doris_connection():
    return pymysql.connect(host=os.environ["DORIS_HOST"], port=9030,
                           user=os.environ["DORIS_USER"], password=os.environ["DORIS_PASSWORD"],
                           database="jsondoc_gateway", autocommit=True, charset="utf8mb4")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/", response_class=HTMLResponse)
def home(request: Request):
    with doris_connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT object_key,file_name,content_type,byte_size,sha256,uploaded_at,object_uri,document_id,document_type FROM file_metadata ORDER BY uploaded_at DESC")
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
    now = datetime.now(timezone.utc)
    digest = hashlib.sha256(raw).hexdigest()
    safe_name = re.sub(r"[^A-Za-z0-9._-]", "_", file.filename)
    key = f"uploads/{now:%Y/%m/%d}/{digest[:12]}-{safe_name}"
    content_type = file.content_type or "application/json"
    minio.put_object(bucket, key, io.BytesIO(raw), len(raw), content_type=content_type)
    uri = f"http://{os.environ['MINIO_PUBLIC_ENDPOINT']}/{bucket}/{key}"
    doc_id = str(doc.get("id", "")) if isinstance(doc, dict) else ""
    doc_type = str(doc.get("type", "")) if isinstance(doc, dict) else ""
    sql = """INSERT INTO polaris_iceberg.jsondoc.file_metadata
      (object_key,file_name,content_type,byte_size,sha256,uploaded_at,object_uri,document_id,document_type)
      VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)"""
    try:
        with doris_connection() as conn, conn.cursor() as cur:
            cur.execute(sql, (key, safe_name, content_type, len(raw), digest,
                              now.replace(tzinfo=None), uri, doc_id, doc_type))
    except Exception:
        try:
            minio.remove_object(bucket, key)
        finally:
            raise
    return RedirectResponse(url="/", status_code=303)
