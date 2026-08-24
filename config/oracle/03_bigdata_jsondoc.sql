-- Replace with object_uri selected from JSONDOC_FILE_METADATA_V.
DEFINE object_uri = 'http://141.148.12.16:9000/jsondocs/uploads/2026/08/21/0687e33ff87c-customer-001.json'

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

CREATE OR REPLACE VIEW customer_jsondoc_v AS
SELECT json_value(data,'$.id' RETURNING VARCHAR2(100)) document_id,
       json_value(data,'$.type' RETURNING VARCHAR2(100)) document_type,
       json_value(data,'$.name' RETURNING VARCHAR2(200)) customer_name,
       data
FROM selected_jsondoc_ext;

SELECT document_id, document_type, customer_name FROM customer_jsondoc_v;
