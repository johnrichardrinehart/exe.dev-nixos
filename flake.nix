{
  description = "A Nix-built OCI image shaped for exe.dev custom VMs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    { nixpkgs, ... }:
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

          runtimePackages = with pkgs; [
            bashInteractive
            cacert
            coreutils-full
            curl
            findutils
            git
            gnugrep
            gnused
            gnutar
            gzip
            iproute2
            less
            nix
            openssh
            procps
            python3
            shadow
            tini
            tzdata
            util-linux
            wget
            which
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
            ];
            text = ''
              set -eu

              mkdir -p /run/sshd /run/exe-dev /var/log /tmp /home/exedev/.ssh /home/john/.ssh
              chmod 0755 /run/sshd /run/exe-dev /var/log
              chmod 1777 /tmp
              chmod 700 /home/exedev/.ssh /home/john/.ssh
              chown -R exedev:exedev /home/exedev || true
              chown -R john:exedev /home/john || true

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

          runtimeRoot = pkgs.buildEnv {
            name = "exe-dev-runtime-root";
            paths = runtimePackages ++ [ init ];
            pathsToLink = [
              "/bin"
              "/libexec"
              "/sbin"
            ];
          };

          rootLayerCommands = ''
            mkdir -p \
              ./etc/nix \
              ./etc/profile.d \
              ./etc/ssh \
              ./etc/ssl/certs \
              ./home/exedev \
              ./home/john \
              ./nix/var/nix/gcroots/per-user/exedev \
              ./nix/var/nix/gcroots/per-user/john \
              ./nix/var/nix/gcroots/per-user/root \
              ./nix/var/nix/profiles/per-user/exedev \
              ./nix/var/nix/profiles/per-user/john \
              ./nix/var/nix/profiles/per-user/root \
              ./root \
              ./run \
              ./srv/www \
              ./tmp \
              ./usr/bin \
              ./var/empty \
              ./var/log

            cat > ./etc/passwd <<'EOF'
            root:x:0:0:root:/root:/bin/bash
            exedev:x:1000:1000:exe.dev user:/home/exedev:/bin/bash
            john:x:1001:1000:local ssh compatibility user:/home/john:/bin/bash
            nixbld1:x:30001:30000:Nix build user 1:/var/empty:/sbin/nologin
            nixbld2:x:30002:30000:Nix build user 2:/var/empty:/sbin/nologin
            nixbld3:x:30003:30000:Nix build user 3:/var/empty:/sbin/nologin
            nixbld4:x:30004:30000:Nix build user 4:/var/empty:/sbin/nologin
            nixbld5:x:30005:30000:Nix build user 5:/var/empty:/sbin/nologin
            nixbld6:x:30006:30000:Nix build user 6:/var/empty:/sbin/nologin
            nixbld7:x:30007:30000:Nix build user 7:/var/empty:/sbin/nologin
            nixbld8:x:30008:30000:Nix build user 8:/var/empty:/sbin/nologin
            nixbld9:x:30009:30000:Nix build user 9:/var/empty:/sbin/nologin
            nixbld10:x:30010:30000:Nix build user 10:/var/empty:/sbin/nologin
            sshd:x:30011:30011:sshd privilege separation user:/var/empty:/sbin/nologin
            EOF

            cat > ./etc/group <<'EOF'
            root:x:0:
            users:x:100:
            exedev:x:1000:exedev,john
            nixbld:x:30000:nixbld1,nixbld2,nixbld3,nixbld4,nixbld5,nixbld6,nixbld7,nixbld8,nixbld9,nixbld10
            sshd:x:30011:
            EOF

            cat > ./etc/shadow <<'EOF'
            root:!:1::::::
            exedev:!:1::::::
            john:!:1::::::
            nixbld1:!:1::::::
            nixbld2:!:1::::::
            nixbld3:!:1::::::
            nixbld4:!:1::::::
            nixbld5:!:1::::::
            nixbld6:!:1::::::
            nixbld7:!:1::::::
            nixbld8:!:1::::::
            nixbld9:!:1::::::
            nixbld10:!:1::::::
            sshd:!:1::::::
            EOF

            cat > ./etc/nsswitch.conf <<'EOF'
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

            cat > ./etc/profile <<'EOF'
            export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/nix/var/nix/profiles/default/bin
            export SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
            export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
            export USER="$(id -un 2>/dev/null || echo exedev)"
            export HOME="$(getent passwd "$USER" | cut -d: -f6)"
            EOF

            cat > ./etc/profile.d/nix.sh <<'EOF'
            export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/nix/var/nix/profiles/default/bin:$PATH
            export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt
            EOF

            cat > ./etc/nix/nix.conf <<'EOF'
            experimental-features = nix-command flakes
            sandbox = false
            build-users-group = nixbld
            trusted-users = root exedev john
            substituters = https://cache.nixos.org/
            trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWGuJSngDLi9PB0dxEIoH5U8vKf1c=
            EOF

            cat > ./etc/motd <<'EOF'
            exe.dev Nix image

            This image is built by Nix and includes a PTY-capable login environment,
            OpenSSH, and the Nix CLI with flakes enabled.
            EOF

            cat > ./srv/www/index.html <<'EOF'
            <!doctype html>
            <html>
              <head><meta charset="utf-8"><title>exe.dev Nix image</title></head>
              <body>
                <h1>exe.dev Nix image</h1>
                <p>The image booted and the HTTP proxy can reach port 80.</p>
              </body>
            </html>
            EOF

            ln -s /bin/env ./usr/bin/env
            ln -s /bin/bash ./usr/bin/bash
            ln -s /run ./var/run
            ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt ./etc/ssl/certs/ca-bundle.crt

            chmod 0644 ./etc/passwd ./etc/group ./etc/nsswitch.conf ./etc/profile ./etc/nix/nix.conf
            chmod 0400 ./etc/shadow
            chmod 0755 ./root ./home/exedev ./home/john ./var/empty
            chmod 1777 ./tmp
          '';

          image = pkgs.dockerTools.buildLayeredImage {
            name = imageName;
            tag = "latest";
            created = "1970-01-01T00:00:01Z";
            contents = [ runtimeRoot ];
            includeNixDB = true;
            maxLayers = 120;
            fakeRootCommands = rootLayerCommands + ''
              chown 0:0 ./root
              chown 1000:1000 ./home/exedev
              chown 1001:1000 ./home/john
            '';
            config = {
              Cmd = [ "/bin/exe-dev-init" ];
              Env = [
                "PATH=/bin:/sbin:/usr/bin:/usr/sbin:/nix/var/nix/profiles/default/bin"
                "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
                "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
                "NIX_REMOTE=daemon"
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
