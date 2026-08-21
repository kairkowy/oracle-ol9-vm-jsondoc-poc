# 5. Apache Polaris 1.7 VM

Polaris binary distribution과 Admin Tool은 같은 1.7.0 버전을 사용합니다. Java 21 이상이 필요합니다.

```sh
dnf install -y java-21-openjdk-headless
useradd --system --home-dir /opt/polaris --shell /sbin/nologin polaris
tar -xzf polaris-bin-1.7.0.tgz -C /opt
ln -s /opt/<실제-polaris-1.7.0-directory> /opt/polaris
chown -R polaris:polaris /opt/<실제-polaris-1.7.0-directory>
install -d -o root -g polaris -m 0750 /etc/polaris
install -o root -g polaris -m 0640 config/polaris/polaris.env.example /etc/polaris/polaris.env
vi /etc/polaris/polaris.env
```

PostgreSQL schema와 root realm을 최초 한 번 bootstrap합니다.

```sh
set -a
. /etc/polaris/polaris.env
set +a
sudo -u polaris /opt/polaris/bin/admin bootstrap \
  -r POLARIS \
  -c POLARIS,root,'<POLARIS_ROOT_CLIENT_SECRET>'
```

Admin Tool과 server 버전은 반드시 일치해야 합니다. bootstrap을 schema migration 명령으로 사용하지 않습니다.

서비스를 설치합니다.

```sh
install -m 0644 config/polaris/polaris.service /etc/systemd/system/polaris.service
systemctl daemon-reload
systemctl enable --now polaris
journalctl -u polaris -f
```

검증:

```sh
curl -fsS http://polaris.labs.localhost.com:8182/q/health
curl -fsS -X POST \
  -H 'Polaris-Realm: POLARIS' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode client_id=root \
  --data-urlencode client_secret='<실제암호>' \
  --data-urlencode scope='PRINCIPAL_ROLE:ALL' \
  http://polaris.labs.localhost.com:8181/api/catalog/v1/oauth/tokens | jq .
```

Catalog 생성은 `scripts/create-polaris-catalog.py`를 Polaris VM에서 실행합니다. `endpoint`와 `endpointInternal` 모두 VM MinIO FQDN을 사용합니다.

```sh
POLARIS_ROOT_CLIENT_SECRET='<실제암호>' \
MINIO_ROOT_PASSWORD='<실제암호>' \
python3 scripts/create-polaris-catalog.py
```
