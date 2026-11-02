#!/usr/bin/env bash
# Creates a local, self-signed code-signing certificate in a private keychain so that every build of
# AutoClicker carries the same signature. macOS ties the Accessibility grant to the signature of the
# app, so with a stable one you allow the app once instead of after every rebuild (an ad-hoc signature
# changes whenever the binary changes).
#
# Nothing is added to the login keychain, to the keychain search list or to the trust settings: the
# certificate lives in its own keychain file and is only ever used by scripts/build-app.sh.
set -euo pipefail

NAME="${SIGNING_NAME:-AutoClicker Local Signing}"
DIR="${AUTOCLICKER_SIGNING_DIR:-$HOME/Library/Application Support/AutoClicker/signing}"
KEYCHAIN="$DIR/AutoClicker.keychain-db"
PASSWORD_FILE="$DIR/keychain-password"
OPENSSL=/usr/bin/openssl

if [ -f "$KEYCHAIN" ] && [ -f "$PASSWORD_FILE" ] \
   && security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$NAME\""; then
  echo "Signing identity \"$NAME\" already exists in $KEYCHAIN"
  exit 0
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

umask 077
PASSWORD="$("$OPENSSL" rand -hex 24)"
printf '%s' "$PASSWORD" > "$PASSWORD_FILE"

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -passout pass:export -out "$TMP/cert.p12"

rm -f "$KEYCHAIN"
security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"                       # never lock automatically
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P export -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null

echo "Created signing identity \"$NAME\" in $KEYCHAIN"
echo "Builds now use it automatically. Allow the app once more in Accessibility after the next install."
