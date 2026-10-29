#!/bin/bash
#
# Run a command while keeping a fresh Anthropic WIF identity token on disk.
#
# Claude Code re-reads ANTHROPIC_IDENTITY_TOKEN_FILE on every token exchange, and
# STS web identity tokens are short-lived (and single-use when they carry a jti),
# so a token written once at startup stops working. This wrapper mints a token on
# the host before running the command, then re-mints it every
# WIF_TOKEN_REFRESH_SECONDS until the command exits.
#
# The token is written to $WIF_TOKEN_DIR/token with an atomic rename. Mount the
# directory, not the file: a single-file bind mount would keep the old inode.
#
# Usage: WIF_TOKEN_DIR=<dir> AWS_PROFILE=<profile> ./scripts/with-wif-token.sh <command...>
#
# The directory is removed when the command exits.

set -euo pipefail

TOKEN_DIR="${WIF_TOKEN_DIR:?WIF_TOKEN_DIR must be set}"
PROFILE="${AWS_PROFILE:?AWS_PROFILE must be set}"
REFRESH="${WIF_TOKEN_REFRESH_SECONDS:-60}"
AUDIENCE="https://api.anthropic.com"

mkdir -p "$TOKEN_DIR"
chmod 700 "$TOKEN_DIR"

# Mint with the SSO profile, not the exported session credentials, so botocore
# refreshes role credentials for as long as the SSO session is valid.
mint() {
  env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN \
    python3 -I - "$PROFILE" "$AUDIENCE" "$TOKEN_DIR" <<'PY'
import os
import sys
import tempfile
import boto3

profile, audience, token_dir = sys.argv[1:4]
token = boto3.Session(profile_name=profile).client("sts", region_name="us-east-1").get_web_identity_token(
    Audience=[audience], SigningAlgorithm="RS256", DurationSeconds=900
)["WebIdentityToken"]

fd, tmp = tempfile.mkstemp(dir=token_dir, prefix=".token.")
with os.fdopen(fd, "w") as f:
    f.write(token)
os.replace(tmp, os.path.join(token_dir, "token"))
PY
}

if ! mint; then
  echo "❌ Could not mint an Anthropic WIF identity token (profile $PROFILE)." >&2
  echo "   ➜ Run 'make sso-login', or check the setup with 'make wif-setup ARGS=--check'." >&2
  rm -rf "$TOKEN_DIR"
  exit 1
fi

(
  while sleep "$REFRESH"; do
    mint 2>/dev/null || echo "⚠️  WIF token refresh failed; retrying in ${REFRESH}s (is the SSO session still valid?)" >&2
  done
) &
REFRESHER=$!
disown "$REFRESHER"  # no "Terminated" job message when it is killed on exit
trap 'kill "$REFRESHER" 2>/dev/null || true; rm -rf "$TOKEN_DIR"' EXIT

"$@"
