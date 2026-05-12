{
  description = "A Nix-built OCI image shaped for exe.dev custom VMs";

  inputs = {
    nixSource = {
      url = "github:NixOS/nix/2.31.5";
      flake = false;
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    {
      nixSource,
      nixpkgs,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
            }
          )
        );
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          imageName = "ghcr.io/johnrichardrinehart/exe.dev-nixos";
          profile = "/nix/var/nix/profiles/default";

          extraPackages = with pkgs; [
            gnused
            iproute2
            procps
            python3
            shadow
            tini
            tzdata
            util-linux
            xz
          ];

          init = pkgs.writeShellApplication {
            name = "exe-dev-init";
            runtimeInputs = with pkgs; [
              coreutils-full
              findutils
              gnugrep
              nix
              openssh
              procps
              python3
              shadow
              tini
              util-linux
            ];
            text = ''
              set -eu

              chmod u+w /etc/passwd /etc/group /etc/shadow || true
              grep -q '^tty:' /etc/group || printf '%s\n' 'tty:x:5:' >> /etc/group
              grep -q '^users:' /etc/group || printf '%s\n' 'users:x:100:' >> /etc/group
              grep -q '^exedev:' /etc/group || printf '%s\n' 'exedev:x:1000:exedev,john' >> /etc/group
              grep -q '^sshd:' /etc/group || printf '%s\n' 'sshd:x:30033:' >> /etc/group

              grep -q '^exedev:' /etc/passwd || printf '%s\n' 'exedev:x:1000:1000:exe.dev user:/home/exedev:/bin/sh' >> /etc/passwd
              grep -q '^john:' /etc/passwd || printf '%s\n' 'john:x:1001:1000:local ssh compatibility user:/home/john:/bin/sh' >> /etc/passwd
              grep -q '^sshd:' /etc/passwd || printf '%s\n' 'sshd:x:30033:30033:sshd privilege separation user:/var/empty:${pkgs.shadow}/bin/nologin' >> /etc/passwd

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

              if [ -n "''${EXE_DEV_AUTHORIZED_KEYS:-}" ]; then
                printf '%s\n' "$EXE_DEV_AUTHORIZED_KEYS" > /run/exe-dev/authorized_keys
                chmod 0644 /run/exe-dev/authorized_keys
              fi

              if [ -r /run/exe-dev/authorized_keys ]; then
                install -m 0600 -o exedev -g exedev /run/exe-dev/authorized_keys /home/exedev/.ssh/authorized_keys || true
                install -m 0600 -o john -g exedev /run/exe-dev/authorized_keys /home/john/.ssh/authorized_keys || true
              fi

              [ -f /run/ssh_host_ed25519_key ] || ssh-keygen -q -t ed25519 -f /run/ssh_host_ed25519_key -N ""
              [ -f /run/ssh_host_rsa_key ] || ssh-keygen -q -t rsa -b 4096 -f /run/ssh_host_rsa_key -N ""

              cat > /run/sshd_config <<'SSHD_CONFIG'
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
              Subsystem sftp ${pkgs.openssh}/libexec/sftp-server
              SSHD_CONFIG

              mkdir -p /nix/var/nix/daemon-socket /nix/var/nix/profiles/per-user/root
              chmod 0755 /nix/var/nix /nix/var/nix/daemon-socket || true

              if command -v nix-daemon >/dev/null 2>&1; then
                nix-daemon --daemon >>/var/log/nix-daemon.log 2>&1 &
              fi

              if command -v sshd >/dev/null 2>&1; then
                sshd -D -e -f /run/sshd_config >>/var/log/sshd.log 2>&1 &
              fi

              if command -v python3 >/dev/null 2>&1; then
                python3 -m http.server 80 --directory /srv/www >>/var/log/http.log 2>&1 &
              fi

              echo "exe-dev-init: ready"
              exec tini -- tail -F /var/log/sshd.log /var/log/nix-daemon.log /var/log/http.log
            '';
          };

          exeDevRoot = pkgs.runCommand "exe-dev-root" { } ''
            mkdir -p \
              $out/dev/pts \
              $out/dev/shm \
              $out/etc/profile.d \
              $out/home/exedev \
              $out/home/john \
              $out/proc \
              $out/run \
              $out/srv/www \
              $out/sys \
              $out/usr \
              $out/var/empty \
              $out/var/log \
              $out/var/tmp

            cat > $out/etc/nsswitch.conf <<'EOF'
            passwd: files
            group: files
            shadow: files
            hosts: files dns
            networks: files dns
            protocols: files
            services: files
            ethers: files
            rpc: files
            EOF

            cat > $out/etc/profile <<'EOF'
            export USER="$(id -un 2>/dev/null || printf '%s' "''${USER:-exedev}")"
            case "$USER" in
              root) export HOME="''${HOME:-/root}" ;;
              john) export HOME="''${HOME:-/home/john}" ;;
              exedev) export HOME="''${HOME:-/home/exedev}" ;;
              *) export HOME="''${HOME:-/home/$USER}" ;;
            esac
            export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/nix/var/nix/profiles/default/sbin:/bin:/usr/bin:''${PATH:-}"
            export MANPATH="$HOME/.nix-profile/share/man:/nix/var/nix/profiles/default/share/man:''${MANPATH:-}"
            export SSL_CERT_FILE=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt
            export GIT_SSL_CAINFO=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt
            export NIX_SSL_CERT_FILE=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt
            EOF

            cat > $out/etc/profile.d/nix.sh <<'EOF'
            export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/nix/var/nix/profiles/default/sbin:/bin:/usr/bin:''${PATH:-}"
            export NIX_SSL_CERT_FILE=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt
            EOF

            cat > $out/etc/motd <<'EOF'
            exe.dev Nix image

            This image is built by Nix and includes a PTY-capable login environment,
            OpenSSH, and the Nix CLI with flakes enabled.
            EOF

            cat > $out/srv/www/index.html <<'EOF'
            <!doctype html>
            <html>
              <head><meta charset="utf-8"><title>exe.dev Nix image</title></head>
              <body>
                <h1>exe.dev Nix image</h1>
                <p>The image booted and the HTTP proxy can reach port 80.</p>
              </body>
            </html>
            EOF

            ln -sfn /nix/var/nix/profiles/default/share $out/usr/share
            ln -sfn /run $out/var/run
            ln -sfn ${pkgs.iana-etc}/etc/protocols $out/etc/protocols
            ln -sfn ${pkgs.iana-etc}/etc/services $out/etc/services

            chmod 0644 $out/etc/nsswitch.conf $out/etc/profile $out/etc/motd
            chmod 0755 $out/home/exedev $out/home/john $out/var/empty
            chmod 1777 $out/dev/shm $out/var/tmp
          '';

          nixBase = pkgs.callPackage "${nixSource}/docker.nix" {
            name = "exe-dev-nixos-bootstrap";
            tag = "latest";
            bundleNixpkgs = false;
            extraPkgs = extraPackages ++ [ init ];
            maxLayers = 110;
            nixConf = {
              experimental-features = [
                "nix-command"
                "flakes"
              ];
              sandbox = false;
              build-users-group = "nixbld";
              trusted-users = [
                "root"
                "exedev"
                "john"
              ];
              substituters = [ "https://cache.nixos.org/" ];
              trusted-public-keys = [
                "cache.nixos.org-1:6NCHdD59X431o0gWGuJSngDLi9PB0dxEIoH5U8vKf1c="
              ];
            };
            Cmd = [ "${profile}/bin/exe-dev-init" ];
            Labels = {
              "org.opencontainers.image.title" = "exe.dev-nixos";
              "org.opencontainers.image.description" = "PTY-capable exe.dev image with OpenSSH and Nix";
              "org.opencontainers.image.source" = "https://github.com/johnrichardrinehart/exe.dev-nixos";
              "org.opencontainers.image.url" = "https://github.com/johnrichardrinehart/exe.dev-nixos";
            };
          };

          image = pkgs.dockerTools.buildLayeredImage {
            name = imageName;
            tag = "latest";
            created = "1970-01-01T00:00:01Z";
            fromImage = nixBase;
            contents = [ exeDevRoot ];
            maxLayers = 120;
            config = {
              Cmd = [ "${profile}/bin/exe-dev-init" ];
              User = "0:0";
              Env = [
                "PATH=/nix/var/nix/profiles/default/bin:/nix/var/nix/profiles/default/sbin:/bin:/usr/bin"
                "MANPATH=/nix/var/nix/profiles/default/share/man"
                "SSL_CERT_FILE=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt"
                "GIT_SSL_CAINFO=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt"
                "NIX_SSL_CERT_FILE=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt"
                "NIX_REMOTE=daemon"
                "USER=root"
                "HOME=/root"
              ];
              ExposedPorts = {
                "22/tcp" = { };
                "80/tcp" = { };
              };
              WorkingDir = "/home/exedev";
              Labels = {
                "org.opencontainers.image.title" = "exe.dev-nixos";
                "org.opencontainers.image.description" = "PTY-capable exe.dev image with OpenSSH and Nix";
                "org.opencontainers.image.source" = "https://github.com/johnrichardrinehart/exe.dev-nixos";
                "org.opencontainers.image.url" = "https://github.com/johnrichardrinehart/exe.dev-nixos";
              };
            };
          };
        in
        {
          default = image;
          image = image;
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
