#!/usr/bin/env bash
#
# Admin password utilities. Provides simple, composable functions that return
# values via stdout (no env var side-effects).

set -uo pipefail

# Return an RFC3339 UTC timestamp suitable for ArgoCD admin.passwordMtime
function __phd_get_password_mtime() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

# Generate a secure random plaintext password (uses Python secrets)
function __phd_generate_admin_password() {
    __phd_check_command_installed "python3" || return 1
    python3 - <<'PY'
import secrets
import string

alphabet = string.ascii_letters + string.digits + "!@#$%^&*()-_=+[]{}"
pwd = ''.join(secrets.choice(alphabet) for _ in range(24))
print(pwd)
PY
}

# Bcrypt-hash the provided plaintext password (requires python3 + bcrypt)
function __phd_bcrypt_password() {
    local plaintext="$1"

    if [ -z "$plaintext" ]; then
        __log_error "Plaintext password is required"
        echo "Usage: __phd_bcrypt_password <plaintext>"
        return 1
    fi

    __phd_check_command_installed "python3" || return 1

    if ! python3 -c 'import bcrypt' 2>/dev/null; then
        __log_error "bcrypt is not installed; install it with 'pip install bcrypt'"
        return 1
    fi

    python3 - "$plaintext" <<'PY'
import sys, bcrypt
pw = sys.argv[1].encode('utf-8')
# Keep rounds consistent with create-user.sh default (10); can be tuned later
salt = bcrypt.gensalt(rounds=10)
print(bcrypt.hashpw(pw, salt).decode())
PY
}

# Resolve the plaintext password to use:
# - If PHD_ARGO_ADMIN_PASSWORD is set, use it
# - Otherwise, generate a new secure password
function __phd_resolve_plaintext_password() {
    if [ -n "${PHD_ARGO_ADMIN_PASSWORD:-}" ]; then
        echo -n "$PHD_ARGO_ADMIN_PASSWORD"
        return 0
    fi
    __phd_generate_admin_password
}
