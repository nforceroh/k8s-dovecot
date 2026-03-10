#!/usr/bin/env bash
# Image validation tests for nforceroh/dovecot
# Usage: ./tests/run_tests.sh [image]   (default: nforceroh/dovecot:dev)
set -uo pipefail

IMAGE="${1:-nforceroh/dovecot:dev}"
PASS=0
FAIL=0
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

section() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }
pass()    { echo -e "  ${GREEN}PASS${NC}  $1"; ((PASS++)); }
fail()    { echo -e "  ${RED}FAIL${NC}  $1"; ((FAIL++)); }

# Run a command inside the image with bash as entrypoint (no s6)
irun() { docker run --rm --entrypoint bash "$IMAGE" "$@"; }

# Common env vars used for dovecot init tests
DOVECOT_ENV=(
  -e DB_HOST=dbhost.test
  -e DB_PORT=3307
  -e DB_NAME=testmail
  -e DB_USER=testuser
  -e DB_PASS=testpass
  -e VMAIL_UID=5000
  -e VMAIL_GID=12
  -e HOSTNAME=imap.test.example.com
  -e POSTMASTER=postmaster@test.example.com
  -e DOVEADM_PASSWORD=test-doveadm-secret
  -e SSL_CRT_FILENAME=/etc/dovecot/certs/tls.crt
  -e SSL_KEY_FILENAME=/etc/dovecot/certs/tls.key
  -e DH_FILENAME=/etc/dovecot/certs/dh.pem
  -e SKIP_FTS=y
  -e RSPAMD_HOST=rspamd.test.svc:11334
)

# ---------------------------------------------------------------------------
# Pre-flight: image must exist
# ---------------------------------------------------------------------------
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo -e "${RED}ERROR:${NC} Image '$IMAGE' not found. Run 'make build' first."
  exit 2
fi

# ---------------------------------------------------------------------------
section "Image Structure — required files"
# ---------------------------------------------------------------------------
REQUIRED_FILES=(
  /etc/s6-overlay/s6-rc.d/init-dovecot/run
  /etc/s6-overlay/s6-rc.d/init-sieve/run
  /etc/s6-overlay/s6-rc.d/init-vmail/run
  /etc/s6-overlay/s6-rc.d/svc-dovecot/run
  /configfiles/sieve/default.sieve
  /configfiles/sieve/learn-ham.sieve
  /configfiles/sieve/learn-spam.sieve
  /configfiles/sieve/moveToPotentialSpam.sieve
  /configfiles/sieve/rspamd_learn_ham.sh
  /configfiles/sieve/rspamd_learn_spam.sh
  /etc/dovecot/dovecot.conf
  /etc/dovecot/conf.d/10-auth.conf
  /etc/dovecot/conf.d/10-logging.conf
  /etc/dovecot/conf.d/10-mail.conf
  /etc/dovecot/conf.d/10-master.conf
  /etc/dovecot/conf.d/15-lda.conf
  /etc/dovecot/conf.d/20-imap.conf
  /etc/dovecot/conf.d/20-lmtp.conf
  /etc/dovecot/conf.d/20-managesieve.conf
  /etc/dovecot/conf.d/20-quota.conf
  /etc/dovecot/conf.d/90-sieve.conf
  /etc/dovecot/conf.d/auth-sql.conf.ext
  /etc/dovecot/conf.d/fts.conf
  /usr/local/bin/optimize-fts.sh
)
for f in "${REQUIRED_FILES[@]}"; do
  if irun -c "[ -f '$f' ]" 2>/dev/null; then
    pass "exists: $f"
  else
    fail "missing: $f"
  fi
done

# ---------------------------------------------------------------------------
section "Image Structure — executables"
# ---------------------------------------------------------------------------
for f in \
  /etc/s6-overlay/s6-rc.d/init-dovecot/run \
  /etc/s6-overlay/s6-rc.d/init-sieve/run \
  /etc/s6-overlay/s6-rc.d/init-vmail/run \
  /etc/s6-overlay/s6-rc.d/svc-dovecot/run \
  /usr/local/bin/optimize-fts.sh; do
  if irun -c "[ -x '$f' ]" 2>/dev/null; then
    pass "executable: $f"
  else
    fail "not executable: $f"
  fi
done

for bin in dovecot doveadm sievec openssl bash sed; do
  if irun -c "command -v $bin >/dev/null 2>&1" 2>/dev/null; then
    pass "binary present: $bin"
  else
    fail "binary missing: $bin"
  fi
done

# ---------------------------------------------------------------------------
section "Image Structure — default environment"
# ---------------------------------------------------------------------------
declare -A EXPECTED_ENV=(
  [TZ]="America/New_York"
  [DB_HOST]="mariadb"
  [DB_PORT]="3306"
  [DB_NAME]="mail"
  [RSPAMD_HOST]="rspamd-svc"
  [DEBUG]="0"
  [SKIP_FTS]="n"
)
for key in "${!EXPECTED_ENV[@]}"; do
  got=$(docker run --rm --entrypoint bash "$IMAGE" -c "echo \${$key}" 2>/dev/null)
  if [ "$got" = "${EXPECTED_ENV[$key]}" ]; then
    pass "ENV $key=${EXPECTED_ENV[$key]}"
  else
    fail "ENV $key: expected '${EXPECTED_ENV[$key]}', got '$got'"
  fi
done

# ---------------------------------------------------------------------------
section "init-vmail"
# ---------------------------------------------------------------------------
out=$(irun -c "bash /etc/s6-overlay/s6-rc.d/init-vmail/run && echo PASS" 2>&1)
if echo "$out" | grep -q "^PASS$"; then
  pass "init-vmail: exits 0"
else
  fail "init-vmail: non-zero exit"
fi
for msg in "Checking for /data/mail" "Checking for /data/sieve"; do
  if echo "$out" | grep -q "$msg"; then
    pass "init-vmail: '$msg'"
  else
    fail "init-vmail: missing output '$msg'"
  fi
done

# ---------------------------------------------------------------------------
section "init-sieve"
# ---------------------------------------------------------------------------
out=$(docker run --rm \
  -e RSPAMD_HOST=rspamd.test.svc:11334 \
  --entrypoint bash "$IMAGE" \
  -c "bash /etc/s6-overlay/s6-rc.d/init-vmail/run && bash /etc/s6-overlay/s6-rc.d/init-sieve/run && echo PASS" 2>&1)

if echo "$out" | grep -q "^PASS$"; then
  pass "init-sieve: exits 0"
else
  fail "init-sieve: non-zero exit"
fi
if echo "$out" | grep -q "Sieve initialization complete"; then
  pass "init-sieve: completion message"
else
  fail "init-sieve: missing completion message"
fi
for sieve in default learn-ham learn-spam moveToPotentialSpam; do
  if echo "$out" | grep -q "Compiling sieve file /data/sieve/${sieve}.sieve"; then
    pass "init-sieve: compiled ${sieve}.sieve"
  else
    fail "init-sieve: did not compile ${sieve}.sieve"
  fi
done

# RSPAMD_HOST placeholder replaced in scripts
sieve_script_contents=$(docker run --rm \
  -e RSPAMD_HOST=rspamd.test.svc:11334 \
  --entrypoint bash "$IMAGE" \
  -c "bash /etc/s6-overlay/s6-rc.d/init-vmail/run >/dev/null 2>&1 && bash /etc/s6-overlay/s6-rc.d/init-sieve/run >/dev/null 2>&1; grep -h '' /data/sieve/rspamd_learn_ham.sh /data/sieve/rspamd_learn_spam.sh" 2>/dev/null)
if echo "$sieve_script_contents" | grep -q "rspamd.test.svc:11334"; then
  pass "init-sieve: RSPAMD_HOST substituted in scripts"
else
  fail "init-sieve: RSPAMD_HOST not substituted in scripts"
fi
if echo "$sieve_script_contents" | grep -q "RSPAMD_HOST"; then
  fail "init-sieve: literal 'RSPAMD_HOST' still present in scripts (substitution failed)"
else
  pass "init-sieve: no literal RSPAMD_HOST placeholder remaining"
fi

# ---------------------------------------------------------------------------
section "TLS fixture setup"
# ---------------------------------------------------------------------------
mkdir -p "$TMPDIR/certs"
docker run --rm \
  -v "$TMPDIR/certs:/certs" \
  --entrypoint sh "$IMAGE" -c \
  "openssl req -x509 -newkey rsa:2048 -keyout /certs/tls.key -out /certs/tls.crt \
     -days 1 -nodes -subj '/CN=test' 2>/dev/null \
   && openssl dhparam -out /certs/dh.pem 512 2>/dev/null" 2>/dev/null

if [ -f "$TMPDIR/certs/tls.crt" ] && [ -f "$TMPDIR/certs/tls.key" ] && [ -f "$TMPDIR/certs/dh.pem" ]; then
  pass "TLS fixtures generated (cert, key, 512-bit DH)"
else
  fail "TLS fixture generation failed — skipping init-dovecot tests"
  FAIL=$((FAIL + 1))
  # Print summary without running further tests that depend on certs
  echo -e "\nResults: $PASS/$((PASS + FAIL)) passed"
  exit 1
fi

# ---------------------------------------------------------------------------
section "init-dovecot — config generation"
# ---------------------------------------------------------------------------
dovecot_out=$(docker run --rm \
  "${DOVECOT_ENV[@]}" \
  -v "$TMPDIR/certs:/etc/dovecot/certs:ro" \
  --entrypoint bash "$IMAGE" \
  -c "bash /etc/s6-overlay/s6-rc.d/init-vmail/run \
   && bash /etc/s6-overlay/s6-rc.d/init-sieve/run \
   && bash /etc/s6-overlay/s6-rc.d/init-dovecot/run \
   && echo PASS" 2>&1)

if echo "$dovecot_out" | grep -q "^PASS$"; then
  pass "init-dovecot: exits 0 (including doveconf validation)"
else
  fail "init-dovecot: non-zero exit"
  echo "--- init-dovecot output (last 30 lines) ---"
  echo "$dovecot_out" | tail -30
  echo "---"
fi

# Capture generated config files for content checks
generated=$(docker run --rm \
  "${DOVECOT_ENV[@]}" \
  -v "$TMPDIR/certs:/etc/dovecot/certs:ro" \
  --entrypoint bash "$IMAGE" \
  -c "bash /etc/s6-overlay/s6-rc.d/init-vmail/run 2>/dev/null \
   && bash /etc/s6-overlay/s6-rc.d/init-sieve/run 2>/dev/null \
   && bash /etc/s6-overlay/s6-rc.d/init-dovecot/run 2>/dev/null; \
  echo '---authsql---'; cat /etc/dovecot/conf.d/auth-sql.conf.ext; \
   echo '---lda---'; cat /etc/dovecot/conf.d/15-lda.conf; \
   echo '---doveadm---'; cat /etc/dovecot/conf.d/91-doveadm.conf; \
   echo '---dovecot---'; cat /etc/dovecot/dovecot.conf; \
  echo '---ssl---'; cat /etc/dovecot/conf.d/10-ssl.conf" 2>/dev/null)

check_conf() {
  local desc="$1" pattern="$2"
  if echo "$generated" | grep -q "$pattern"; then
    pass "config: $desc"
  else
    fail "config: $desc (pattern: $pattern)"
  fi
}

# auth-sql.conf.ext
check_conf "sql driver block mysql maildb" "^mysql maildb [{]"
check_conf "sql DB host"                   "host = dbhost.test"
check_conf "sql DB port"                   "port = 3307"
check_conf "sql DB name"                   "dbname = testmail"
check_conf "sql DB user"                   "user = testuser"
check_conf "sql pass_scheme"               "passdb_default_password_scheme = SHA512-CRYPT"
check_conf "sql passdb query present"      "passdb_sql_query ="
check_conf "sql userdb query present"      "userdb_sql_query ="
check_conf "sql userdb iterate present"    "userdb_sql_iterate_query ="

# 15-lda.conf
check_conf "lda hostname"                 "hostname=imap.test.example.com"
check_conf "lda postmaster_address"       "postmaster_address=postmaster@test.example.com"
check_conf "lda recipient_delimiter"      "recipient_delimiter=+"
check_conf "lda autocreate=yes"           "lda_mailbox_autocreate.*=yes"
check_conf "lda autosubscribe=yes"        "lda_mailbox_autosubscribe.*=yes"
check_conf "lda mail_plugins sieve"       "mail_plugins.*sieve"

# 91-doveadm.conf
check_conf "doveadm port 3333"            "port = 3333"
check_conf "doveadm password set"         "doveadm_password = test-doveadm-secret"

# dovecot.conf
check_conf "login_greeting set"           "login_greeting=Ready"
check_conf "dovecot_config_version set"   "dovecot_config_version=2\.4\.2"
check_conf "dovecot_storage_version set"  "dovecot_storage_version=2\.4\.2"

# 10-ssl.conf
check_conf "ssl=required"                 "ssl = required"
check_conf "ssl_server_cert_file path"    "ssl_server_cert_file = /etc/dovecot/certs/tls.crt"
check_conf "ssl_server_key_file path"     "ssl_server_key_file = /etc/dovecot/certs/tls.key"

# auth-sql.conf.ext — group must be 'mail' not 'vmail'
check_conf "auth-sql gid=mail (not gid=vmail)" "gid = mail"
if echo "$generated" | grep -q "gid=vmail"; then
  fail "auth-sql: gid=vmail found (should be gid=mail)"
else
  pass "auth-sql: no gid=vmail (correct)"
fi

# ---------------------------------------------------------------------------
section "init-dovecot — doveadm disabled when no password"
# ---------------------------------------------------------------------------
no_pw_out=$(docker run --rm \
  "${DOVECOT_ENV[@]}" \
  -e DOVEADM_PASSWORD= \
  -v "$TMPDIR/certs:/etc/dovecot/certs:ro" \
  --entrypoint bash "$IMAGE" \
  -c "bash /etc/s6-overlay/s6-rc.d/init-dovecot/run 2>/dev/null; cat /etc/dovecot/conf.d/91-doveadm.conf" 2>/dev/null)
if echo "$no_pw_out" | grep -qE "^doveadm_password\s*="; then
  fail "doveadm: password line written when DOVEADM_PASSWORD is empty"
else
  pass "doveadm: no password line when DOVEADM_PASSWORD is empty"
fi

# ---------------------------------------------------------------------------
section "init-dovecot — SSL cert absent causes exit 1"
# ---------------------------------------------------------------------------
ssl_fail_out=$(docker run --rm \
  "${DOVECOT_ENV[@]}" \
  --entrypoint bash "$IMAGE" \
  -c "bash /etc/s6-overlay/s6-rc.d/init-dovecot/run; echo exit_code=\$?" 2>&1)
if echo "$ssl_fail_out" | grep -q "exit_code=1"; then
  pass "init-dovecot: exits 1 when SSL cert is missing"
else
  fail "init-dovecot: expected exit 1 for missing SSL cert, got something else"
fi
if echo "$ssl_fail_out" | grep -q "ERROR: SSL certificate not found"; then
  pass "init-dovecot: meaningful error message for missing SSL cert"
else
  fail "init-dovecot: no clear error message for missing SSL cert"
fi

# ---------------------------------------------------------------------------
section "Summary"
# ---------------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo ""
echo "Results: ${PASS}/${TOTAL} passed"
if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}${FAIL} test(s) failed${NC}"
  exit 1
else
  echo -e "${GREEN}All tests passed!${NC}"
fi
