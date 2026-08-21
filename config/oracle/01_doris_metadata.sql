-- Run as the Oracle application owner (LAKE). Substitute the actual Doris password.
CREATE DATABASE LINK doris_link
  CONNECT TO "jsondoc_app" IDENTIFIED BY "CHANGE_ME"
  USING 'DORIS_GATEWAY';

SELECT COUNT(*) FROM "jsondoc_gateway"."file_metadata"@doris_link;

CREATE OR REPLACE VIEW jsondoc_file_metadata_v AS
SELECT
  "object_key" AS object_key, "file_name" AS file_name,
  "content_type" AS content_type, "byte_size" AS byte_size,
  "sha256" AS sha256, "uploaded_at" AS uploaded_at,
  "object_uri" AS object_uri, "document_id" AS document_id,
  "document_type" AS document_type
FROM "jsondoc_gateway"."file_metadata"@doris_link;
