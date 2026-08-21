#!/bin/sh
set -eu

ORACLE_HOME=/home/oracle/app/oracle/dbhome
export ORACLE_HOME
PATH="$ORACLE_HOME/bin:$PATH"
export PATH

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
HS_ADMIN="$ORACLE_HOME/hs/admin"
NET_ADMIN="$ORACLE_HOME/network/admin"
LISTENER_FILE="$NET_ADMIN/listener.ora"
TNSNAMES_FILE="$NET_ADMIN/tnsnames.ora"

if grep -q '/absolute/path/to/vendor' "$PROJECT_DIR/oracle/gateway/listener-snippet.ora"; then
  echo "ERROR: Replace the vendor library placeholder in listener-snippet.ora first." >&2
  exit 1
fi

if [ ! -f /etc/odbc.ini ]; then
  echo "ERROR: /etc/odbc.ini is missing. Install and test the Trino DSN first." >&2
  exit 1
fi

if [ ! -f /etc/odbcinst.ini ]; then
  echo "ERROR: /etc/odbcinst.ini is missing. Register the Simba driver first." >&2
  exit 1
fi

if grep -q '/absolute/path/to' /etc/odbcinst.ini; then
  echo "ERROR: Replace the Simba Driver placeholder in /etc/odbcinst.ini first." >&2
  exit 1
fi

if [ ! -x "$ORACLE_HOME/bin/dg4odbc" ]; then
  echo "ERROR: $ORACLE_HOME/bin/dg4odbc not found or not executable." >&2
  echo "Install Oracle Database Gateway for ODBC in this ORACLE_HOME first." >&2
  exit 1
fi

mkdir -p "$HS_ADMIN" "$NET_ADMIN"
cp "$PROJECT_DIR/oracle/gateway/initTRINO.ora" "$HS_ADMIN/initTRINO.ora"

touch "$LISTENER_FILE" "$TNSNAMES_FILE"
cp -p "$LISTENER_FILE" "$LISTENER_FILE.bak"
cp -p "$TNSNAMES_FILE" "$TNSNAMES_FILE.bak"

if ! grep -q '^LISTENER_TRINO[[:space:]]*=' "$LISTENER_FILE"; then
  printf '\n' >> "$LISTENER_FILE"
  sed '/^#/d' "$PROJECT_DIR/oracle/gateway/listener-snippet.ora" >> "$LISTENER_FILE"
  echo "Added LISTENER_TRINO to $LISTENER_FILE"
else
  echo "LISTENER_TRINO already exists; listener.ora was not appended."
fi

if ! grep -q '^TRINO_GATEWAY[[:space:]]*=' "$TNSNAMES_FILE"; then
  printf '\n' >> "$TNSNAMES_FILE"
  sed '/^#/d' "$PROJECT_DIR/oracle/network/tnsnames-snippet.ora" >> "$TNSNAMES_FILE"
  echo "Added TRINO_GATEWAY to $TNSNAMES_FILE"
else
  echo "TRINO_GATEWAY already exists; tnsnames.ora was not appended."
fi

echo "Copied init file to $HS_ADMIN/initTRINO.ora"
echo "Backups: $LISTENER_FILE.bak and $TNSNAMES_FILE.bak"
echo "Next: install/copy oracle/gateway/odbc.ini as /etc/odbc.ini, then run:"
echo "  lsnrctl start LISTENER_TRINO"
echo "  tnsping TRINO_GATEWAY"
