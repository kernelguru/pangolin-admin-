#!/usr/bin/env bash
# Starts a throwaway OpenSSH server on 127.0.0.1:2222 that trusts a test SSH CA,
# and creates certificate-signed user keys for the PangolinSSH integration tests.
#
#   D=$(mktemp -d) && scripts/ssh-test-server.sh "$D"
#   PANGOLIN_SSH_TEST_DIR="$D" swift test --filter PangolinSSHTests
#   kill "$(cat "$D/sshd.pid")"
set -euo pipefail
D="${1:?usage: $0 <empty-directory>}"
USER_NAME="$(id -un)"
cd "$D"
ssh-keygen -q -t ed25519 -N "" -C test-ca -f ca
ssh-keygen -q -t ed25519 -N "" -f host_ed25519
ssh-keygen -q -t ed25519 -N "" -f user_ed && ssh-keygen -q -s ca -I ed -n "$USER_NAME" -V -5m:+1h user_ed.pub
ssh-keygen -q -t ecdsa -b 256 -N "" -f user_ec && ssh-keygen -q -s ca -I ec -n "$USER_NAME" -V -5m:+1h user_ec.pub
ssh-keygen -q -t ed25519 -N "" -f user_wrongprincipal && ssh-keygen -q -s ca -I wrong -n someoneelse -V -5m:+1h user_wrongprincipal.pub
ssh-keygen -q -t ed25519 -N secret -f user_encrypted
ssh-keygen -lf host_ed25519.pub | awk '{print $2}' > host_fingerprint
cat > sshd_config <<CFG
Port 2222
ListenAddress 127.0.0.1
HostKey $D/host_ed25519
TrustedUserCAKeys $D/ca.pub
AuthorizedKeysFile none
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
UsePAM no
StrictModes no
PidFile $D/sshd.pid
CFG
chmod 600 host_ed25519
mkdir -p /run/sshd 2>/dev/null || true
"$(command -v sshd || echo /usr/sbin/sshd)" -f sshd_config -E "$D/sshd.log"
