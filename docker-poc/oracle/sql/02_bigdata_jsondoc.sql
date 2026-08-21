-- Oracle AI Database 26ai. The lab bucket is public-read for a zero-credential demo.
-- For production use HTTPS and com.oracle.bigdata.credential.name.
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE jsondoc_ext PURGE';
EXCEPTION WHEN OTHERS THEN
  IF SQLCODE != -942 THEN RAISE; END IF;
END;
/

CREATE TABLE jsondoc_ext (data JSON)
ORGANIZATION EXTERNAL
(
  TYPE ORACLE_BIGDATA
  ACCESS PARAMETERS
  (
    com.oracle.bigdata.fileformat = jsondoc
  )
  LOCATION ('http://woko.labs.localhost.com:9000/jsondocs/uploads/2026/08/21/0687e33ff87c-customer-001.json')
)
REJECT LIMIT UNLIMITED;

CREATE OR REPLACE VIEW customer_jsondoc_v AS
SELECT
  json_value(data, '$.id' RETURNING VARCHAR2(100)) AS document_id,
  json_value(data, '$.type' RETURNING VARCHAR2(100)) AS document_type,
  json_value(data, '$.name' RETURNING VARCHAR2(200)) AS customer_name,
  data
FROM jsondoc_ext;

SELECT document_id, document_type, customer_name FROM customer_jsondoc_v;
