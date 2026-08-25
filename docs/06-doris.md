# 6. VM2 Apache Doris FE + BE

Apache Doris 4.0.1 FE와 BE를 VM2 Private IP `10.0.27.145` 한 VM에서 실행합니다. FE는 SQL 접속·계획을, BE는 Iceberg scan과 INSERT 실행을 담당하므로 둘 다 필요합니다. 업무 데이터의 source of truth는 VM1 MinIO이며 BE disk는 작업·cache 용도로 사용합니다.

## 설치

```sh
sudo dnf install -y java-17-openjdk-headless mariadb
sudo useradd --system --home-dir /opt/doris --shell /sbin/nologin doris
```

`mariadb` 패키지는 Doris FE의 MySQL protocol 점검과 BE 등록에 사용하는
`mysql`, `mysqladmin` client를 제공합니다. Doris binary 자체에는 이 client가
포함되지 않습니다.

OpenJDK의 실제 설치 경로는 OL9 package update마다 달라질 수 있으므로 고정
경로를 사용하지 않습니다. 아래 명령으로 Java home을 계산합니다.

```sh
JAVA_BIN=$(readlink -f "$(command -v java)")
JAVA_HOME=$(dirname "$(dirname "$JAVA_BIN")")
echo "$JAVA_HOME"
test -x "$JAVA_HOME/bin/java" && echo 'Java: OK'
```

Doris BE 기동 전에 kernel map limit을 영구 설정하고 swap을 해제해야 합니다.

```sh
sudo tee /etc/sysctl.d/99-doris.conf >/dev/null <<'EOF'
vm.max_map_count = 2000000
EOF
sudo sysctl --system
sysctl vm.max_map_count

swapon --show
sudo swapoff -a
swapon --show
```

재부팅 후에도 swap이 활성화되지 않게 하려면 `/etc/fstab`의 활성 swap 행을
주석 처리합니다. 변경 전에는 반드시 백업합니다.

```sh
sudo cp -a /etc/fstab /etc/fstab.before-doris
grep -nE '^[^#].*\\sswap\\s' /etc/fstab
sudo vi /etc/fstab
```

`bin-x64` 배포본은 AVX2 CPU용입니다. 먼저 `grep -m1 -o avx2 /proc/cpuinfo`로 확인합니다. 출력이 없으면 아래 URL의 `bin-x64` 대신 `bin-x64-noavx2` 배포본을 사용해야 합니다. 공식 배포처에서 binary와 SHA-512을 내려받아 검증한 뒤 `/opt`에 풉니다.

```sh
DORIS_VERSION=4.0.1
curl -fLO https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-${DORIS_VERSION}-bin-x64.tar.gz
curl -fLO https://apache-doris-releases.oss-accelerate.aliyuncs.com/apache-doris-${DORIS_VERSION}-bin-x64.tar.gz.sha512
expected=$(awk '{print $1}' apache-doris-${DORIS_VERSION}-bin-x64.tar.gz.sha512)
echo "${expected}  apache-doris-${DORIS_VERSION}-bin-x64.tar.gz" | sha512sum --check -

sudo tar -xzf apache-doris-${DORIS_VERSION}-bin-x64.tar.gz -C /opt
# Archive directory: /opt/apache-doris-4.0.1-bin-x64
sudo ln -sfnT /opt/apache-doris-${DORIS_VERSION}-bin-x64 /opt/doris
sudo chown -R doris:doris /opt/apache-doris-${DORIS_VERSION}-bin-x64
sudo restorecon -RFv /opt/apache-doris-${DORIS_VERSION}-bin-x64
ls -ld /opt/doris /opt/doris/fe/conf /opt/doris/be/conf
```

`/opt/doris`는 실제 archive directory가 아니라 위에서 만든 symlink입니다. 이후 문서의 `/opt/doris/fe`와 `/opt/doris/be` 경로는 각각 배포본의 `fe/`, `be/`를 가리킵니다.

```sh
sudo install -d -o doris -g doris -m 0750 /var/lib/doris/fe-meta /var/lib/doris/be-storage
sudo cp config/doris/fe.conf /opt/doris/fe/conf/fe.conf
sudo cp config/doris/be.conf /opt/doris/be/conf/be.conf
sudo sed -i "s|^JAVA_HOME = .*|JAVA_HOME = ${JAVA_HOME}|" \
  /opt/doris/fe/conf/fe.conf /opt/doris/be/conf/be.conf
sudo -u doris test -x "$JAVA_HOME/bin/java" && echo 'Doris Java: OK'
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
  -e "ALTER SYSTEM ADD BACKEND '10.0.27.145:9050'"
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
iceberg.rest.uri=http://10.0.121.203:8181/api/catalog
s3.endpoint=http://10.0.121.203:9000
use_path_style=true
```

`s3.use_path_style`은 사용하지 않습니다.

```sh
mysql -h127.0.0.1 -P9030 -uroot \
  -e 'SHOW CREATE CATALOG polaris_iceberg\G'
```

## VM2 자원 배분

24 GB RAM 기준으로 BE 12~14 GB, FE heap 4 GB, App 1~2 GB, 나머지를 OS/cache에 남기는 것을 출발점으로 합니다. `/var/lib/doris/fe-meta`는 영구 보존하고 `/var/lib/doris/be-storage`에는 50 GB 이상의 작업 공간을 준비합니다. `priority_networks=10.0.27.145/32`로 FE/BE가 Public NAT IP가 아닌 VNIC Private IP를 advertise하게 합니다. 메모리 제한값은 실제 부하 시험 후 조정하십시오.
