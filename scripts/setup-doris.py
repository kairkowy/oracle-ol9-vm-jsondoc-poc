#!/usr/bin/env python3
import os
import time
import pymysql

host = os.getenv("DORIS_HOST", "127.0.0.1")
app_user = os.getenv("DORIS_APP_USER", "jsondoc_app")
password = os.environ["DORIS_APP_PASSWORD"]
polaris_secret = os.environ["POLARIS_ROOT_CLIENT_SECRET"]
minio_user = os.getenv("MINIO_ROOT_USER", "minioadmin")
minio_password = os.environ["MINIO_ROOT_PASSWORD"]


def q(value):
    return "'" + value.replace("'", "''") + "'"


for attempt in range(60):
    try:
        conn = pymysql.connect(host=host, port=9030, user="root", password="", autocommit=True)
        break
    except pymysql.MySQLError:
        if attempt == 59:
            raise
        time.sleep(2)

with conn.cursor() as cur:
    cur.execute("SHOW BACKENDS")
    backend_hosts = {str(row[1]) for row in cur.fetchall()}
    if "doris-be.labs.localhost.com" not in backend_hosts:
        cur.execute("ALTER SYSTEM ADD BACKEND 'doris-be.labs.localhost.com:9050'")

    cur.execute("SHOW CATALOGS")
    catalogs = {str(row[0]) for row in cur.fetchall()}
    if "polaris_iceberg" not in catalogs:
        cur.execute(f"""CREATE CATALOG `polaris_iceberg` PROPERTIES (
      'type'='iceberg', 'iceberg.catalog.type'='rest',
      'iceberg.rest.uri'='http://polaris.labs.localhost.com:8181/api/catalog',
      'warehouse'='jsondoc_catalog',
      'iceberg.rest.security.type'='oauth2',
      'iceberg.rest.oauth2.credential'={q('root:' + polaris_secret)},
      'iceberg.rest.oauth2.server-uri'='http://polaris.labs.localhost.com:8181/api/catalog/v1/oauth/tokens',
      'iceberg.rest.oauth2.scope'='PRINCIPAL_ROLE:ALL',
      'iceberg.rest.vended-credentials-enabled'='false',
      's3.endpoint'='http://minio.labs.localhost.com:9000',
      's3.access_key'={q(minio_user)}, 's3.secret_key'={q(minio_password)},
      's3.region'='us-east-1', 'use_path_style'='true'
        )""")
    cur.execute("CREATE DATABASE IF NOT EXISTS `polaris_iceberg`.`jsondoc`")
    cur.execute("""CREATE TABLE IF NOT EXISTS `polaris_iceberg`.`jsondoc`.`file_metadata` (
      object_key STRING, file_name STRING, content_type STRING, byte_size BIGINT,
      sha256 STRING, uploaded_at DATETIME(6), object_uri STRING,
      document_id STRING, document_type STRING
    ) PROPERTIES ('format-version'='2')""")
    cur.execute("CREATE DATABASE IF NOT EXISTS `jsondoc_gateway`")
    cur.execute("DROP VIEW IF EXISTS `jsondoc_gateway`.`file_metadata`")
    cur.execute("CREATE VIEW `jsondoc_gateway`.`file_metadata` AS SELECT * FROM `polaris_iceberg`.`jsondoc`.`file_metadata`")
    cur.execute(f"CREATE USER IF NOT EXISTS {q(app_user)} IDENTIFIED BY {q(password)}")
    cur.execute(f"GRANT ADMIN_PRIV ON *.*.* TO {q(app_user)}")

print("Doris backend, catalog, Iceberg table, view, and app user are ready")
