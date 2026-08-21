-- Run as the application schema owner. Substitute a secret or wallet-based link.
-- Some ODBC drivers use an empty user/password for Trino NONE authentication.
CREATE DATABASE LINK trino_link
  CONNECT TO "jsondoc_app" IDENTIFIED BY "replace-me"
  USING 'TRINO_GATEWAY';

CREATE OR REPLACE VIEW jsondoc_file_metadata_v AS
SELECT
  "object_key"    AS object_key,
  "file_name"     AS file_name,
  "content_type"  AS content_type,
  "byte_size"     AS byte_size,
  "sha256"        AS sha256,
  "uploaded_at"   AS uploaded_at,
  "object_uri"    AS object_uri,
  "document_id"   AS document_id,
  "document_type" AS document_type
-- Oracle remote object syntax supports schema.table@dblink, not
-- Trino's catalog.schema.table. Catalog=iceberg is selected in odbc.ini.
FROM "jsondoc"."file_metadata"@trino_link;

SELECT file_name, byte_size, object_uri
FROM jsondoc_file_metadata_v
ORDER BY uploaded_at DESC;
