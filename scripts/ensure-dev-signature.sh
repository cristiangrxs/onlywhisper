#!/usr/bin/env bash
# Creates a stable local code-signing identity for OnlyWhisper Dev.
# macOS ties Input Monitoring and Accessibility to the signature. Ad-hoc
# signing changes on every build, so those permissions are dropped. This
# certificate stays the same, so a granted permission survives rebuilds.
set -euo pipefail

NAME="OnlyWhisper Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

has_identity() {
  security find-identity -v -p codesigning | grep -q "\"$NAME\""
}

if has_identity; then
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if ! security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$work/cert.pem" 2>/dev/null; then
  cat > "$work/cert.conf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

  openssl req -new -newkey rsa:2048 -x509 -days 3650 -nodes \
    -keyout "$work/key.pem" \
    -out "$work/cert.pem" \
    -config "$work/cert.conf" >/dev/null 2>&1

  openssl pkcs12 -export \
    -inkey "$work/key.pem" \
    -in "$work/cert.pem" \
    -out "$work/cert.p12" \
    -passout pass:owdev >/dev/null 2>&1

  security import "$work/cert.p12" \
    -k "$KEYCHAIN" \
    -P owdev \
    -A \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null
fi

security add-trusted-cert -r trustRoot -k "$KEYCHAIN" "$work/cert.pem"
has_identity
