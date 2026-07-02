#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="Just Chat Local Code Signing"
SUPPORT_DIR="${HOME}/Library/Application Support/JustChat/CodeSigning"
KEYCHAIN_PATH="$SUPPORT_DIR/JustChatLocal.keychain-db"
PASSWORD_FILE="$SUPPORT_DIR/keychain-password"
WORK_DIR="$SUPPORT_DIR/work"

mkdir -p "$SUPPORT_DIR"
chmod 700 "$SUPPORT_DIR"

if [[ ! -f "$PASSWORD_FILE" ]]; then
  umask 077
  uuidgen > "$PASSWORD_FILE"
fi
KEYCHAIN_PASSWORD="$(cat "$PASSWORD_FILE")"

if [[ ! -f "$KEYCHAIN_PATH" ]]; then
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

existing_identity="$(
  security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null \
    | awk -v name="$IDENTITY_NAME" '$0 ~ name { print $2; exit }'
)"

if [[ -n "$existing_identity" ]]; then
  echo "$existing_identity"
  exit 0
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
chmod 700 "$WORK_DIR"

if security find-certificate -c "$IDENTITY_NAME" -p "$KEYCHAIN_PATH" > "$WORK_DIR/existing.crt" 2>/dev/null; then
  security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$KEYCHAIN_PATH" \
    "$WORK_DIR/existing.crt" \
    >/dev/null 2>&1 || true

  existing_identity="$(
    security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null \
      | awk -v name="$IDENTITY_NAME" '$0 ~ name { print $2; exit }'
  )"

  if [[ -n "$existing_identity" ]]; then
    echo "$existing_identity"
    exit 0
  fi
fi

cat > "$WORK_DIR/cert.conf" <<EOF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_codesign
prompt = no

[ req_distinguished_name ]
CN = $IDENTITY_NAME

[ v3_codesign ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -nodes \
  -days 3650 \
  -keyout "$WORK_DIR/identity.key" \
  -out "$WORK_DIR/identity.crt" \
  -config "$WORK_DIR/cert.conf" \
  >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -legacy \
  -out "$WORK_DIR/identity.p12" \
  -inkey "$WORK_DIR/identity.key" \
  -in "$WORK_DIR/identity.crt" \
  -name "$IDENTITY_NAME" \
  -passout "pass:$KEYCHAIN_PASSWORD" \
  >/dev/null 2>&1

security import "$WORK_DIR/identity.p12" \
  -k "$KEYCHAIN_PATH" \
  -P "$KEYCHAIN_PASSWORD" \
  -T /usr/bin/codesign \
  >/dev/null

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN_PATH" \
  "$WORK_DIR/identity.crt" \
  >/dev/null

security set-key-partition-list \
  -S apple-tool:,apple: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH" \
  >/dev/null

identity="$(
  security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null \
    | awk -v name="$IDENTITY_NAME" '$0 ~ name { print $2; exit }'
)"

if [[ -z "$identity" ]]; then
  echo "Failed to create local code signing identity." >&2
  exit 1
fi

echo "$identity"
