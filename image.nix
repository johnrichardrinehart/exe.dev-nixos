{
  pkgs,
  nixSource,
  imageName ? "exe-dev-nixos",
}:

let
  profile = "/nix/var/nix/profiles/default";

  labels = {
    "org.opencontainers.image.title" = "exe.dev-nixos";
    "org.opencontainers.image.description" = "PTY-capable exe.dev image with OpenSSH, Nix, and Shelley";
  };

  shelleyVersion = "0.634.915524700";
  shelleySystem =
    {
      x86_64-linux = {
        arch = "amd64";
        hash = "sha256-bWNe+raRhq3QsLSZG6tYBO3PDqjTQWjpbNcheg6/x8I=";
      };
      aarch64-linux = {
        arch = "arm64";
        hash = "sha256-j0jMpYHwBcCziT8db53lCaStoAx1mIR7kebRDW3ouIQ=";
      };
    }
    .${pkgs.stdenv.hostPlatform.system}
      or (throw "unsupported Shelley platform: ${pkgs.stdenv.hostPlatform.system}");

  shelley = pkgs.stdenvNoCC.mkDerivation {
    pname = "shelley";
    version = shelleyVersion;

    src = pkgs.fetchurl {
      url = "https://github.com/boldsoftware/shelley/releases/download/v${shelleyVersion}/shelley_linux_${shelleySystem.arch}";
      hash = shelleySystem.hash;
    };

    dontUnpack = true;

    installPhase = ''
      install -Dm755 $src $out/bin/shelley
    '';

    meta = {
      description = "Mobile-friendly web-based coding agent for exe.dev";
      homepage = "https://github.com/boldsoftware/shelley";
      license = pkgs.lib.licenses.asl20;
      mainProgram = "shelley";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  };

  extraPackages = with pkgs; [
    bashInteractive
    gnused
    iproute2
    procps
    python3
    shadow
    shelley
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
      shelley
      tini
      util-linux
    ];
    text = ''
      export NLOGIN=${pkgs.shadow}/bin/nologin
      export SSHD=${pkgs.openssh}/bin/sshd
      export SFTP_SERVER=${pkgs.openssh}/libexec/sftp-server
    ''
    + builtins.readFile ./scripts/exe-dev-init.sh;
  };

  exeDevRoot = pkgs.runCommand "exe-dev-root" { } ''
    mkdir -p $out
    cp -R ${./rootfs}/. $out/
    chmod -R u+w $out

    mkdir -p \
      $out/dev/pts \
      $out/dev/shm \
      $out/home/exedev \
      $out/proc \
      $out/run \
      $out/sys \
      $out/usr \
      $out/var/empty \
      $out/var/log \
      $out/var/tmp

    ln -sfn /nix/var/nix/profiles/default/share $out/usr/share
    ln -sfn /run $out/var/run
    ln -sfn ${pkgs.iana-etc}/etc/protocols $out/etc/protocols
    ln -sfn ${pkgs.iana-etc}/etc/services $out/etc/services

    mkdir -p $out/exe.dev
    cat > $out/exe.dev/shelley.json <<'JSON'
    {
      "llm_gateway": "http://169.254.169.254/gateway/llm"
    }
    JSON

    chmod 0644 $out/etc/nsswitch.conf $out/etc/profile $out/etc/profile.d/nix.sh $out/etc/motd $out/exe.dev/shelley.json
    chmod 0755 $out/home/exedev $out/var/empty
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
      ];
      substituters = [ "https://cache.nixos.org/" ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWGuJSngDLi9PB0dxEIoH5U8vKf1c="
      ];
    };
    Cmd = [ "${profile}/bin/exe-dev-init" ];
    Labels = labels;
  };
in
pkgs.dockerTools.buildLayeredImage {
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
      "PATH=${profile}/bin:${profile}/sbin:/bin:/usr/bin"
      "MANPATH=${profile}/share/man"
      "SSL_CERT_FILE=${profile}/etc/ssl/certs/ca-bundle.crt"
      "GIT_SSL_CAINFO=${profile}/etc/ssl/certs/ca-bundle.crt"
      "NIX_SSL_CERT_FILE=${profile}/etc/ssl/certs/ca-bundle.crt"
      "NIX_REMOTE=daemon"
      "USER=root"
      "HOME=/root"
    ];
    ExposedPorts = {
      "22/tcp" = { };
      "80/tcp" = { };
      "9999/tcp" = { };
    };
    WorkingDir = "/home/exedev";
    Labels = labels;
  };
}
