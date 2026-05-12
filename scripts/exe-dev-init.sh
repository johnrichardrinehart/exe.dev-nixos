set -eu

chmod u+w /etc/passwd /etc/group /etc/shadow || true
grep -q '^tty:' /etc/group || printf '%s\n' 'tty:x:5:' >> /etc/group
grep -q '^users:' /etc/group || printf '%s\n' 'users:x:100:' >> /etc/group
grep -q '^exedev:' /etc/group || printf '%s\n' 'exedev:x:1000:exedev,john' >> /etc/group
grep -q '^sshd:' /etc/group || printf '%s\n' 'sshd:x:30033:' >> /etc/group

grep -q '^exedev:' /etc/passwd || printf '%s\n' 'exedev:x:1000:1000:exe.dev user:/home/exedev:/bin/sh' >> /etc/passwd
grep -q '^john:' /etc/passwd || printf '%s\n' 'john:x:1001:1000:local ssh compatibility user:/home/john:/bin/sh' >> /etc/passwd
grep -q '^sshd:' /etc/passwd || printf '%s\n' "sshd:x:30033:30033:sshd privilege separation user:/var/empty:${NLOGIN}" >> /etc/passwd

grep -q '^exedev:' /etc/shadow || printf '%s\n' 'exedev:!:1::::::' >> /etc/shadow
grep -q '^john:' /etc/shadow || printf '%s\n' 'john:!:1::::::' >> /etc/shadow
grep -q '^sshd:' /etc/shadow || printf '%s\n' 'sshd:!:1::::::' >> /etc/shadow
chmod 0644 /etc/passwd /etc/group || true
chmod 0400 /etc/shadow || true

mkdir -p /dev /dev/pts /dev/shm /proc /sys /run/sshd /run/exe-dev /var/log /tmp /home/exedev/.ssh /home/john/.ssh
chmod 0755 /run/sshd /run/exe-dev /var/log
chmod 1777 /tmp
chmod 1777 /dev/shm || true
chmod 700 /home/exedev/.ssh /home/john/.ssh

for home in /home/exedev /home/john; do
  ln -sfn /nix/var/nix/profiles/default "$home/.nix-profile"
  mkdir -p "$home/.nix-defexpr"
  ln -sfn /nix/var/nix/profiles/per-user/root/channels "$home/.nix-defexpr/channels"
done

chown exedev:exedev /home/exedev || true
chown -R exedev:exedev /home/exedev/.ssh /home/exedev/.nix-defexpr || true
chown john:exedev /home/john || true
chown -R john:exedev /home/john/.ssh /home/john/.nix-defexpr || true

mountpoint -q /proc || mount -t proc proc /proc || true
mountpoint -q /dev/pts || mount -t devpts devpts /dev/pts -o gid=5,mode=620,ptmxmode=666 || true
[ -e /dev/ptmx ] || ln -s pts/ptmx /dev/ptmx || true

: > /var/log/sshd.log
: > /var/log/nix-daemon.log
: > /var/log/http.log

if [ -n "${EXE_DEV_AUTHORIZED_KEYS:-}" ]; then
  printf '%s\n' "$EXE_DEV_AUTHORIZED_KEYS" > /run/exe-dev/authorized_keys
  chmod 0644 /run/exe-dev/authorized_keys
fi

if [ -r /run/exe-dev/authorized_keys ]; then
  install -m 0600 -o exedev -g exedev /run/exe-dev/authorized_keys /home/exedev/.ssh/authorized_keys || true
  install -m 0600 -o john -g exedev /run/exe-dev/authorized_keys /home/john/.ssh/authorized_keys || true
fi

[ -f /run/ssh_host_ed25519_key ] || ssh-keygen -q -t ed25519 -f /run/ssh_host_ed25519_key -N ""
[ -f /run/ssh_host_rsa_key ] || ssh-keygen -q -t rsa -b 4096 -f /run/ssh_host_rsa_key -N ""

cat > /run/sshd_config <<SSHD_CONFIG
Port 22
HostKey /run/ssh_host_ed25519_key
HostKey /run/ssh_host_rsa_key
AuthorizedKeysFile .ssh/authorized_keys /run/exe-dev/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
UsePAM no
X11Forwarding no
AllowTcpForwarding yes
PermitTTY yes
PrintMotd no
PidFile /run/sshd.pid
Subsystem sftp ${SFTP_SERVER}
SSHD_CONFIG

mkdir -p /nix/var/nix/daemon-socket /nix/var/nix/profiles/per-user/root
chmod 0755 /nix/var/nix /nix/var/nix/daemon-socket || true

if command -v nix-daemon >/dev/null 2>&1; then
  nix-daemon --daemon >> /var/log/nix-daemon.log 2>&1 &
fi

if command -v sshd >/dev/null 2>&1; then
  sshd -D -e -f /run/sshd_config >> /var/log/sshd.log 2>&1 &
fi

if command -v python3 >/dev/null 2>&1; then
  python3 -m http.server 80 --directory /srv/www >> /var/log/http.log 2>&1 &
fi

echo "exe-dev-init: ready"
exec tini -- tail -F /var/log/sshd.log /var/log/nix-daemon.log /var/log/http.log
