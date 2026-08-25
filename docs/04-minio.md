# 4. VM1 MinIO

POC parity를 위해 `RELEASE.2025-07-23T15-54-02Z` x86-64 RPM을 사용합니다. 공식 MinIO 배포처에서 RPM을 내려받아 checksum/signature를 검증한 후 설치합니다.

```sh
sudo dnf install -y ./minio-20250723155402.0.0-1.x86_64.rpm
getent group minio >/dev/null || sudo groupadd --system minio
id minio >/dev/null 2>&1 || sudo useradd --system --gid minio \
  --home-dir /var/lib/minio --create-home --shell /sbin/nologin minio
sudo install -d -o minio -g minio -m 0750 /var/lib/minio/data
sudo install -o root -g minio -m 0640 config/minio/minio.env.example /etc/default/minio
sudo vi /etc/default/minio

# 공식 RPM unit은 새 host에서 존재하지 않는 서비스 계정을 참조할 수 있다.
# 패키지 원본 unit은 변경하지 않고, 위에서 만든 계정으로 실행하도록 override한다.
sudo install -d -m 0755 /etc/systemd/system/minio.service.d
sudo tee /etc/systemd/system/minio.service.d/override.conf >/dev/null <<'EOF'
[Service]
User=minio
Group=minio
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now minio
```

`MINIO_CONFIG_ENV_FILE=/etc/default/minio` causes the MinIO process itself to
read the file after systemd switches to `User=minio`. Therefore `root:root 0600`
is not usable with this unit; retain `root:minio 0640` so the service can read
the secret without making it world-readable.

RPM이 만든 service의 `User`, `EnvironmentFile`, `ExecStart`가 실제 설치와 맞는지 확인합니다.

```sh
sudo systemctl cat minio
sudo systemctl show minio -p User -p Group
sudo systemctl status minio
curl -fsS -o /dev/null -w 'HTTP %{http_code}\n' \
  http://127.0.0.1:9000/minio/health/live
```

MinIO Client를 관리 VM 또는 VM1에 설치하고 초기화합니다.

```sh
curl -fLO https://dl.min.io/client/mc/release/linux-amd64/mc
sudo install -m 0755 mc /usr/local/bin/mc
mc --version
mc alias set poc http://127.0.0.1:9000 minioadmin '<실제암호>'
mc mb --ignore-existing poc/jsondocs
```

`mc`는 MinIO Server RPM에 포함되지 않습니다. 위 명령은 `x86_64` Intel/AMD
Linux용 `linux-amd64` binary를 내려받습니다. `/usr/local/bin` 설치만 root
권한이 필요하며, 이후 `mc` 명령은 `opc` 같은 관리 OS 계정으로 실행합니다.

Oracle `ORACLE_BIGDATA`의 무자격증명 HTTP POC를 위해서만 bucket 읽기를 공개합니다.

```sh
mc anonymous set download poc/jsondocs
mc anonymous get poc/jsondocs
```

운영에서는 public access를 제거하고 HTTPS 및 Oracle credential을 사용합니다.

```sh
mc anonymous set none poc/jsondocs
```

검증:

```sh
mc cp samples/customer-001.json poc/jsondocs/samples/customer-001.json
mc stat poc/jsondocs/samples/customer-001.json
curl -f http://141.148.12.16:9000/jsondocs/samples/customer-001.json
```

MinIO VM 자체에서 OCI public IP로 접근하는 hairpin NAT 검증은 신뢰할 수
없습니다. 같은 VM에서는 `127.0.0.1` 또는 private IP를 사용하고, 공인 IP
접근은 App/Oracle VM처럼 별도 호스트에서 검증합니다. 외부 검증 전 OCI
NSG/Security List와 OS firewall에서 TCP 9000을 필요한 source CIDR에만
허용하십시오.

Doris catalog에서는 MinIO virtual-host 방식이 아니라 반드시 다음 값을 사용합니다.

```text
s3.endpoint=http://10.0.121.203:9000
use_path_style=true
```

`s3.use_path_style`이 아니라 `use_path_style`입니다. 잘못 설정하면 Doris BE가 `bucket.hostname`을 해석하다 `curlCode: 6`으로 실패합니다.
