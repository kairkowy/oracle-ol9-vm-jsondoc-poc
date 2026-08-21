#!/bin/sh
set -eu

ORACLE_HOME=/home/oracle/app/oracle/dbhome
export ORACLE_HOME
ODBCINI=/etc/odbc.ini
export ODBCINI

fail=0
check_file() {
  if [ -e "$1" ]; then
    echo "OK: $1"
  else
    echo "MISSING: $1" >&2
    fail=1
  fi
}

check_file "$ORACLE_HOME/bin/dg4odbc"
check_file "$ORACLE_HOME/hs/admin/initTRINO.ora"
check_file "$ORACLE_HOME/network/admin/listener.ora"
check_file "$ORACLE_HOME/network/admin/tnsnames.ora"
check_file "$ODBCINI"
check_file /etc/odbcinst.ini
check_file /usr/lib64/libodbc.so.2

if command -v odbcinst >/dev/null 2>&1; then
  echo "--- unixODBC configuration ---"
  odbcinst -j
  echo "--- System DSNs ---"
  odbcinst -q -s || fail=1
else
  echo "MISSING: odbcinst (install unixODBC)" >&2
  fail=1
fi

if [ -x "$ORACLE_HOME/bin/dg4odbc" ]; then
  echo "--- dg4odbc unresolved libraries ---"
  unresolved=$(ldd "$ORACLE_HOME/bin/dg4odbc" | grep 'not found' || true)
  if [ -n "$unresolved" ]; then
    echo "$unresolved" >&2
    fail=1
  else
    echo "OK: no unresolved dg4odbc libraries"
  fi
fi

driver_name=$(awk -F= '
  /^\[TrinoProd\]/{in_dsn=1; next}
  /^\[/{in_dsn=0}
  in_dsn && /^[[:space:]]*Driver[[:space:]]*=/{
    sub(/^[^=]*=/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit
  }
' "$ODBCINI" 2>/dev/null || true)

if [ -n "$driver_name" ]; then
  driver=$(odbcinst -q -d -n "$driver_name" 2>/dev/null | awk -F= '
    /^[[:space:]]*Driver[[:space:]]*=/{
      sub(/^[^=]*=/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit
    }
  ' || true)
  if [ -z "$driver" ]; then
    echo "MISSING: ODBC driver registration [$driver_name]" >&2
    fail=1
  else
    check_file "$driver"
  fi
  if [ -n "$driver" ] && [ -f "$driver" ]; then
    echo "--- ODBC driver unresolved libraries ---"
    unresolved=$(ldd "$driver" | grep 'not found' || true)
    if [ -n "$unresolved" ]; then
      echo "$unresolved" >&2
      fail=1
    else
      echo "OK: no unresolved ODBC driver libraries"
    fi
  fi
else
  echo "MISSING: Driver entry in [TrinoProd] DSN" >&2
  fail=1
fi

exit "$fail"
