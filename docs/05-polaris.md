# 5. VM1 Apache Polaris 1.7

Polaris binary distribution과 Admin Tool은 같은 1.7.0 버전을 사용합니다. Java 21 이상이 필요합니다.

Polaris와 PostgreSQL은 같은 VM이므로 JDBC URL은 `jdbc:postgresql://127.0.0.1:5432/polaris`를 사용합니다. PostgreSQL이 준비된 뒤 Polaris를 시작합니다.

```sh
sudo dnf install -y java-21-openjdk-headless
getent group polaris >/dev/null || sudo groupadd --system polaris
id polaris >/dev/null 2>&1 || sudo useradd --system --gid polaris \
  --home-dir /opt/polaris --shell /sbin/nologin polaris

POLARIS_VERSION=1.7.0
curl -fLO https://downloads.apache.org/polaris/${POLARIS_VERSION}/polaris-bin-${POLARIS_VERSION}.tgz
curl -fLO https://downloads.apache.org/polaris/${POLARIS_VERSION}/polaris-bin-${POLARIS_VERSION}.tgz.sha512
expected=$(awk '{print $1}' polaris-bin-${POLARIS_VERSION}.tgz.sha512)
echo "${expected}  polaris-bin-${POLARIS_VERSION}.tgz" | sha512sum --check -

sudo tar -xzf polaris-bin-${POLARIS_VERSION}.tgz -C /opt
sudo ln -sfnT /opt/polaris-bin-${POLARIS_VERSION} /opt/polaris
sudo chown -R polaris:polaris /opt/polaris-bin-${POLARIS_VERSION}
sudo chmod 755 /opt/polaris-bin-${POLARIS_VERSION}/bin/admin \
  /opt/polaris-bin-${POLARIS_VERSION}/bin/server
# archive를 /home 아래에서 내려받았으므로 /opt 이동 후 SELinux label을 복구한다.
# user_home_t가 남으면 systemd가 203/EXEC으로 실행을 차단한다.
sudo restorecon -RFv /opt/polaris-bin-${POLARIS_VERSION}
sudo install -d -o root -g polaris -m 0750 /etc/polaris
sudo install -o root -g polaris -m 0640 config/polaris/polaris.env.example /etc/polaris/polaris.env
sudo vi /etc/polaris/polaris.env
```

PostgreSQL schema와 root realm을 최초 한 번 bootstrap합니다.

```sh
sudo -u polaris /bin/bash -c '
  set -a
  . /etc/polaris/polaris.env
  set +a
  exec /opt/polaris/bin/admin bootstrap \
    -r POLARIS \
    -c POLARIS,root,"<POLARIS_ROOT_CLIENT_SECRET>"
'
```

Admin Tool과 server 버전은 반드시 일치해야 합니다. bootstrap을 schema migration 명령으로 사용하지 않습니다.

서비스를 설치합니다.

```sh
sudo install -m 0644 config/polaris/polaris.service /etc/systemd/system/polaris.service
sudo systemctl daemon-reload
sudo systemctl enable --now polaris
sudo journalctl -u polaris -f
```

검증:

```sh
curl -fsS http://127.0.0.1:8182/q/health
curl -fsS -X POST \
  -H 'Polaris-Realm: POLARIS' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode client_id=root \
  --data-urlencode client_secret='<실제암호>' \
  --data-urlencode scope='PRINCIPAL_ROLE:ALL' \
  http://127.0.0.1:8181/api/catalog/v1/oauth/tokens | jq .
```

`/q/health`에 MongoDB health check가 함께 보여도 relational-jdbc 사용 여부는
PostgreSQL schema로 확인합니다.

```sh
sudo -u postgres psql -d polaris -c '\\dt polaris_schema.*'
```

Catalog 생성은 `scripts/create-polaris-catalog.py`를 **VM1에서 `opc` 관리 계정으로** 실행합니다. 먼저 `jsondocs` bucket이 존재하고 Polaris가 `UP`인지 확인합니다. VM2 client가 REST catalog에서 받을 `endpoint`는 VM1 Private IP, Polaris가 VM1 내부에서 사용할 `endpointInternal`은 localhost로 분리합니다.

```sh
curl -fsS http://127.0.0.1:8182/q/health
mc ls poc/jsondocs
```

`POLARIS_ROOT_CLIENT_SECRET`은 앞선 `admin bootstrap`에서 root principal에 지정한 값과 정확히 같아야 합니다. `MINIO_ROOT_PASSWORD`는 이 Python 스크립트가 직접 읽지 않습니다. MinIO credential은 이미 `/etc/polaris/polaris.env`의 `AWS_ACCESS_KEY_ID`와 `AWS_SECRET_ACCESS_KEY`로 Polaris 서비스에 전달돼 있어야 합니다.

```sh
POLARIS_BASE_URL='http://127.0.0.1:8181' \
POLARIS_REALM='POLARIS' \
POLARIS_ROOT_CLIENT_ID='root' \
POLARIS_CATALOG='jsondoc_catalog' \
MINIO_BUCKET='jsondocs' \
MINIO_ENDPOINT='http://10.0.27.145:9000' \
MINIO_ENDPOINT_INTERNAL='http://127.0.0.1:9000' \
POLARIS_ROOT_CLIENT_SECRET='<실제암호>' \
python3 scripts/create-polaris-catalog.py
```

성공 시 `Created jsondoc_catalog: HTTP 201` 또는 이미 생성된 경우 `Catalog jsondoc_catalog already exists`가 출력됩니다. `401`/`403`이면 root client secret 또는 bootstrap 상태를, `Connection refused`이면 Polaris service 상태를 확인합니다.
