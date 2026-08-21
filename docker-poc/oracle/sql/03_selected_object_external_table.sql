-- SQL*Plus/SQLcl helper for the second step of the JSONDoc flow:
-- 1. Search object_uri through the Oracle metadata view.
-- 2. Put one selected URI in object_uri below.
-- 3. Recreate the external table and read that JSON document directly from MinIO.
--
-- LOCATION is DDL metadata, so a normal SQL bind variable cannot be used here.
-- LAKE must already have private-target network ACL privileges (resolve/http/connect)
-- for woko.labs.localhost.com:9000.
DEFINE object_uri = 'http://woko.labs.localhost.com:9000/jsondocs/uploads/2026/08/21/0687e33ff87c-customer-001.json'

BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE selected_jsondoc_ext PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE selected_jsondoc_ext (data JSON)
ORGANIZATION EXTERNAL
(
  TYPE ORACLE_BIGDATA
  ACCESS PARAMETERS (com.oracle.bigdata.fileformat = jsondoc)
  LOCATION ('&object_uri')
)
REJECT LIMIT UNLIMITED;

SELECT
  json_value(data, '$.id' RETURNING VARCHAR2(100)) AS document_id,
  json_value(data, '$.type' RETURNING VARCHAR2(100)) AS document_type,
  json_value(data, '$.name' RETURNING VARCHAR2(200)) AS customer_name
FROM selected_jsondoc_ext;

SELECT json_serialize(data PRETTY) AS document
FROM selected_jsondoc_ext;
