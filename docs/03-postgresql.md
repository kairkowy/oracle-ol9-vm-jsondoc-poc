# 3. VM1 PostgreSQL 17

PostgreSQL은 Polaris 전용 영속 저장소입니다. JSON/Parquet 파일을 저장하지 않습니다.

Oracle Linux 9 기본 module과 PGDG repository를 혼합하지 마십시오. `postgresql17-server`와 `postgresql17`은 기본 AppStream에 없는 **PGDG versioned package**이므로, 먼저 PGDG repository RPM을 등록해야 합니다. 인터넷 직접 설치가 금지된 환경에서는 아래 RPM과 checksum을 검증해 내부 저장소에 반입한 뒤 그 내부 URL을 사용합니다.

```sh
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo dnf -qy module disable postgresql
sudo dnf clean all
sudo dnf install -y postgresql17-server postgresql17
sudo /usr/pgsql-17/bin/postgresql-17-setup initdb
sudo systemctl enable --now postgresql-17
```

`/var/lib/pgsql/17/data/postgresql.conf`:

```ini
listen_addresses = '127.0.0.1'
port = 5432
password_encryption = 'scram-sha-256'
```

Polaris가 같은 VM에서 접속하므로 `/var/lib/pgsql/17/data/pg_hba.conf`에는 loopback만 허용합니다.

```text
host    polaris    polaris    127.0.0.1/32    scram-sha-256
```

DB와 계정을 생성합니다. 템플릿의 비밀번호를 먼저 변경하십시오.

```sh
sudo -u postgres psql -v ON_ERROR_STOP=1 \
  -f config/postgresql/10-polaris.sql
sudo systemctl restart postgresql-17
```

검증:

```sh
sudo ss -ltnp | grep 5432
psql 'host=127.0.0.1 port=5432 dbname=polaris user=polaris sslmode=prefer'
```

POC에서도 `/var/lib/pgsql/17/data`를 정기 백업하고, Polaris upgrade 전에 DB snapshot을 만듭니다. Polaris relational-jdbc schema migration은 자동으로 수행된다고 가정하지 않습니다.
