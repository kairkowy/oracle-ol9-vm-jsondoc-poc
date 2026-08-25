# 6. VM2 Apache Doris FE + BE

Apache Doris 4.0.1 FE와 BE를 VM2 Private IP `10.0.121.203` 한 VM에서 실행합니다. FE는 SQL 접속·계획을, BE는 Iceberg scan과 INSERT 실행을 담당하므로 둘 다 필요합니다. 업무 데이터의 source of truth는 VM1 MinIO이며 BE disk는 작업·cache 용도로 사용합니다.

## 설치

```sh
sudo dnf install -y java-17-openjdk-headless
sudo useradd --system --home-dir /opt/doris --shell /sbin/nologin doris
```

배포본의 `fe/`, `be/`를 각각 `/opt/doris/fe`, `/opt/doris/be`에 설치합니다.

```sh
sudo install -d -o doris -g doris -m 0750 /var/lib/doris/fe-meta /var/lib/doris/be-storage
sudo cp config/doris/fe.conf /opt/doris/fe/conf/fe.conf
sudo cp config/doris/be.conf /opt/doris/be/conf/be.conf
sudo chown -R doris:doris /opt/doris/fe /opt/doris/be /var/lib/doris
sudo install -m 0644 config/doris/doris-fe.service config/doris/doris-be.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now doris-fe
```

FE의 9030 응답을 확인하고 같은 VM의 BE를 시작·등록합니다.

```sh
mysqladmin -h127.0.0.1 -P9030 -uroot ping
sudo systemctl enable --now doris-be
mysql -h127.0.0.1 -P9030 -uroot \
  -e "ALTER SYSTEM ADD BACKEND '10.0.121.203:9050'"
mysql -h127.0.0.1 -P9030 -uroot -e 'SHOW BACKENDS\G'
```

`SHOW BACKENDS`의 `Alive: true`, `HeartbeatFailureCounter: 0`을 확인합니다. 등록 스크립트는 기존 backend를 확인하므로 이미 등록했다면 중복 추가하지 않습니다.

## Catalog와 객체 초기화

```sh
sudo python3 -m venv /opt/jsondoc-admin-venv
sudo /opt/jsondoc-admin-venv/bin/pip install pymysql==1.1.2
DORIS_HOST=127.0.0.1 \
DORIS_APP_PASSWORD='<실제암호>' \
POLARIS_ROOT_CLIENT_SECRET='<실제암호>' \
MINIO_ROOT_PASSWORD='<실제암호>' \
/opt/jsondoc-admin-venv/bin/python scripts/setup-doris.py
```

VM1의 두 service endpoint가 catalog에 들어가야 합니다.

```text
iceberg.rest.uri=http://10.0.27.145:8181/api/catalog
s3.endpoint=http://10.0.27.145:9000
use_path_style=true
```

`s3.use_path_style`은 사용하지 않습니다.

```sh
mysql -h127.0.0.1 -P9030 -uroot \
  -e 'SHOW CREATE CATALOG polaris_iceberg\G'
```

## VM2 자원 배분

24 GB RAM 기준으로 BE 12~14 GB, FE heap 4 GB, App 1~2 GB, 나머지를 OS/cache에 남기는 것을 출발점으로 합니다. `/var/lib/doris/fe-meta`는 영구 보존하고 `/var/lib/doris/be-storage`에는 50 GB 이상의 작업 공간을 준비합니다. `priority_networks=10.0.121.203/32`로 FE/BE가 Public NAT IP가 아닌 VNIC Private IP를 advertise하게 합니다. 메모리 제한값은 실제 부하 시험 후 조정하십시오.
