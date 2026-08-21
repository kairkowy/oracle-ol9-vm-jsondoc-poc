# 3. PostgreSQL 17 VM

PostgreSQL은 Polaris 전용 영속 저장소입니다. JSON/Parquet 파일을 저장하지 않습니다.

Oracle Linux 9 기본 module과 PGDG repository를 혼합하지 마십시오. PostgreSQL 공식 Red Hat 계열 설치 페이지에서 현재 OL9용 PGDG repository RPM URL을 확인하고, 승인된 내부 저장소에서 설치합니다.

```sh
dnf -qy module disable postgresql
dnf install -y <검증한-pgdg-repository-rpm>
dnf install -y postgresql17-server postgresql17
/usr/pgsql-17/bin/postgresql-17-setup initdb
systemctl enable --now postgresql-17
```

`/var/lib/pgsql/17/data/postgresql.conf`:

```ini
listen_addresses = '192.168.56.13'
port = 5432
password_encryption = 'scram-sha-256'
```

`/var/lib/pgsql/17/data/pg_hba.conf`에 Polaris VM만 허용합니다.

```text
host    polaris    polaris    192.168.56.14/32    scram-sha-256
```

DB와 계정을 생성합니다. 템플릿의 비밀번호를 먼저 변경하십시오.

```sh
sudo -u postgres psql -v ON_ERROR_STOP=1 \
  -f config/postgresql/10-polaris.sql
systemctl restart postgresql-17
```

검증:

```sh
ss -ltnp | grep 5432
psql 'host=192.168.56.13 port=5432 dbname=polaris user=polaris sslmode=prefer'
```

POC에서도 `/var/lib/pgsql/17/data`를 정기 백업하고, Polaris upgrade 전에 DB snapshot을 만듭니다. Polaris relational-jdbc schema migration은 자동으로 수행된다고 가정하지 않습니다.
