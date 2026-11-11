#!/bin/bash
# Creates "Tessera Self-Signed", a free code-signing certificate in your login keychain.
#
# Why bother without a paid Apple Developer account: macOS ties the Accessibility permission to the
# app's signature. Ad-hoc signatures change with every build, so each update would silently lose the
# permission. Builds signed with one stable certificate keep it. (This does not get past Gatekeeper's
# first-launch check — only Apple's paid Developer ID does that.)
#
# Run once; keep the keychain item. Losing it means users re-grant Accessibility once after the
# next update.
set -euo pipefail

NAME="Tessera Self-Signed"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists in your keychain."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSWORD="$(openssl rand -hex 16)"

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# 20 years: re-creating it later would change the signature and cost users a permission re-grant.
openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$WORK/cert.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
# -legacy: macOS's `security` can't read OpenSSL 3's default PKCS#12 encryption.
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -passout "pass:$PASSWORD" -out "$WORK/identity.p12"
# -T: let codesign use the key without a keychain prompt on every build.
security import "$WORK/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$PASSWORD" -T /usr/bin/codesign >/dev/null

echo "Created \"$NAME\" in your login keychain."
