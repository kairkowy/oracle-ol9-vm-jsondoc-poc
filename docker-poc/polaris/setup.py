import json
import os
import urllib.error
import urllib.parse
import urllib.request

base = "http://polaris:8181"
realm = os.getenv("POLARIS_REALM", "POLARIS")
client_id = os.getenv("POLARIS_ROOT_CLIENT_ID", "root")
client_secret = os.environ["POLARIS_ROOT_CLIENT_SECRET"]
catalog = os.getenv("POLARIS_CATALOG", "jsondoc_catalog")
bucket = os.getenv("MINIO_BUCKET", "jsondocs")
public_host = os.getenv("HOSTNAME_FQDN", "woko.labs.localhost.com")


def request(path, *, method="GET", data=None, token=None):
    headers = {"Polaris-Realm": realm, "Accept": "application/json"}
    body = None
    if data is not None:
        body = json.dumps(data).encode()
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.urlopen(
        urllib.request.Request(base + path, data=body, headers=headers, method=method),
        timeout=30,
    )


token_form = urllib.parse.urlencode({
    "grant_type": "client_credentials",
    "client_id": client_id,
    "client_secret": client_secret,
    "scope": "PRINCIPAL_ROLE:ALL",
}).encode()
token_request = urllib.request.Request(
    base + "/api/catalog/v1/oauth/tokens",
    data=token_form,
    headers={"Content-Type": "application/x-www-form-urlencoded", "Polaris-Realm": realm},
    method="POST",
)
with urllib.request.urlopen(token_request, timeout=30) as response:
    token = json.load(response)["access_token"]

payload = {
    "catalog": {
        "name": catalog,
        "type": "INTERNAL",
        "readOnly": False,
        "properties": {
            "default-base-location": f"s3://{bucket}/warehouse",
            "rest-metrics-reporting-enabled": "false",
        },
        "storageConfigInfo": {
            "storageType": "S3",
            "allowedLocations": [f"s3://{bucket}/warehouse"],
            "endpoint": f"http://{public_host}:9000",
            "endpointInternal": "http://minio:9000",
            "pathStyleAccess": True,
            "stsUnavailable": True,
            "region": "us-east-1",
        },
    }
}
try:
    with request("/api/management/v1/catalogs", method="POST", data=payload, token=token) as response:
        print(f"Created Polaris catalog {catalog}: HTTP {response.status}")
except urllib.error.HTTPError as exc:
    if exc.code == 409:
        print(f"Polaris catalog {catalog} already exists")
    else:
        print(exc.read().decode(), flush=True)
        raise
