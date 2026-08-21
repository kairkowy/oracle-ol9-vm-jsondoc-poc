# 6. Apache Doris FE/BE VM

Apache Doris 4.0.1 x86-64 binary distribution을 공식 mirror에서 내려받고 checksum/signature를 검증합니다. FE와 BE는 서로 다른 VM에 설치합니다.

## 공통 준비

```sh
dnf install -y java-17-openjdk-headless
useradd --system --home-dir /opt/doris --shell /sbin/nologin doris
```

FE VM에는 배포본의 `fe/`, BE VM에는 `be/`를 각각 `/opt/doris/fe`, `/opt/doris/be`로 설치합니다. 데이터 디렉터리는 별도 disk를 권장합니다.

### FE VM

```sh
install -d -o doris -g doris -m 0750 /var/lib/doris/fe-meta
cp config/doris/fe.conf /opt/doris/fe/conf/fe.conf
chown -R doris:doris /opt/doris/fe /var/lib/doris/fe-meta
install -m 0644 config/doris/doris-fe.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now doris-fe
```

### BE VM

```sh
install -d -o doris -g doris -m 0750 /var/lib/doris/be-storage
cp config/doris/be.conf /opt/doris/be/conf/be.conf
chown -R doris:doris /opt/doris/be /var/lib/doris/be-storage
install -m 0644 config/doris/doris-be.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now doris-be
```

FE가 먼저 `9030`을 열었는지 확인한 뒤 BE를 등록합니다.

```sh
mysqladmin -hdoris-fe.labs.localhost.com -P9030 -uroot ping
mysql -hdoris-fe.labs.localhost.com -P9030 -uroot \
  -e "ALTER SYSTEM ADD BACKEND 'doris-be.labs.localhost.com:9050'"
```

BE가 등록되기 전에 `SELECT 1`을 healthcheck로 사용하지 않습니다. `SHOW BACKENDS\G`에서 `Alive: true`, `HeartbeatFailureCounter: 0`을 확인합니다.

```sh
mysql -hdoris-fe.labs.localhost.com -P9030 -uroot -e 'SHOW BACKENDS\G'
```

Catalog와 객체를 초기화합니다. 스크립트는 이미 등록된 backend와 catalog를 확인하므로 같은 설정으로 재실행할 수 있습니다. 기존 catalog의 endpoint나 credential을 바꿀 때는 스크립트가 자동 변경하지 않으므로 별도 `ALTER CATALOG` 절차를 사용하십시오.

```sh
python3 -m venv /opt/jsondoc-admin-venv
/opt/jsondoc-admin-venv/bin/pip install pymysql==1.1.2
DORIS_APP_PASSWORD='<실제암호>' \
POLARIS_ROOT_CLIENT_SECRET='<실제암호>' \
MINIO_ROOT_PASSWORD='<실제암호>' \
/opt/jsondoc-admin-venv/bin/python scripts/setup-doris.py
```

중요한 MinIO 설정:

```text
s3.endpoint=http://minio.labs.localhost.com:9000
use_path_style=true
```

`s3.use_path_style`은 사용하지 않습니다. 구성 후 `SHOW CREATE CATALOG polaris_iceberg\G`로 확인합니다.

```sh
mysql -hdoris-fe.labs.localhost.com -P9030 -uroot \
  -e 'SHOW CREATE CATALOG polaris_iceberg\G'
```
