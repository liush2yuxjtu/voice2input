#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="${VOICE2INPUT_SIGN_IDENTITY:-Voice2Input Local Signing}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$ROOT_DIR/build/local-signing"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
P12_PASSWORD="voice2input-local-signing"

if security find-identity -v -p codesigning | grep -Fq "$IDENTITY_NAME"; then
  echo "Signing identity already exists: $IDENTITY_NAME"
  exit 0
fi

mkdir -p "$TMP_DIR"

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -keyout "$TMP_DIR/key.pem" \
  -out "$TMP_DIR/cert.pem" \
  -days 3650 \
  -nodes \
  -subj "/CN=${IDENTITY_NAME}" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -legacy \
  -inkey "$TMP_DIR/key.pem" \
  -in "$TMP_DIR/cert.pem" \
  -out "$TMP_DIR/codesign.p12" \
  -passout "pass:${P12_PASSWORD}" >/dev/null 2>&1

security import "$TMP_DIR/codesign.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -T /usr/bin/codesign >/dev/null

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "" \
  "$KEYCHAIN" >/dev/null

security add-trusted-cert \
  -d \
  -r trustRoot \
  -k "$KEYCHAIN" \
  "$TMP_DIR/cert.pem" >/dev/null

echo "Created signing identity: $IDENTITY_NAME"
