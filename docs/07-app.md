# JSONDoc 앱 VM

대상: `app.labs.localhost.com` (`192.168.56.11`). 앱은 JSON 원본을 MinIO에 올리고 같은 요청에서 Doris의 Iceberg 테이블에 메타정보를 기록합니다. 두 번째 단계가 실패하면 방금 올린 MinIO 객체를 삭제합니다.

## 설치

```bash
sudo dnf install -y python3.12
sudo useradd --system --home-dir /opt/jsondoc --shell /sbin/nologin jsondoc
sudo mkdir -p /opt/jsondoc/app/templates /etc/jsondoc
sudo cp app/main.py app/requirements.txt /opt/jsondoc/app/
sudo cp app/templates/index.html /opt/jsondoc/app/templates/
sudo python3.12 -m venv /opt/jsondoc/venv
sudo /opt/jsondoc/venv/bin/pip install --requirement /opt/jsondoc/app/requirements.txt
sudo cp config/app/jsondoc-app.env.example /etc/jsondoc/app.env
sudo cp config/app/jsondoc-app.service /etc/systemd/system/
sudo chown -R jsondoc:jsondoc /opt/jsondoc
sudo chmod 600 /etc/jsondoc/app.env
```

`/etc/jsondoc/app.env`의 두 비밀번호를 실제 값으로 바꾼 후 시작합니다.

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now jsondoc-app
sudo firewall-cmd --permanent --add-port=8501/tcp
sudo firewall-cmd --reload
curl -fsS http://127.0.0.1:8501/health
```

브라우저에서 `http://app.labs.localhost.com:8501`을 열어 JSON 파일을 업로드합니다. 운영에서는 8501을 직접 공개하지 말고 TLS reverse proxy와 인증을 앞에 둡니다.

## 장애 확인

```bash
sudo journalctl -u jsondoc-app -n 200 --no-pager
curl -I http://minio.labs.localhost.com:9000/minio/health/live
```

Doris BE가 MinIO에 접근하지 못하면 FE의 catalog에서 `use_path_style=true`인지 확인합니다. `s3.use_path_style`은 이 검증 환경에서 동작하지 않았습니다.
