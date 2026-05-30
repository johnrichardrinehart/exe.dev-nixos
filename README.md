# exe.dev-nixos

This repository builds a Nix-based OCI image for exe.dev:

```text
ghcr.io/johnrichardrinehart/exe.dev-nixos:latest
```

It uses the upstream Nix project's `docker.nix` image builder for the Nix
bootstrap layer, then adds a thin exe.dev-specific layer for login and service
behavior. It is not just the stock `nixos/nix` image: that image is a minimal
Nix package-manager container and does not behave like a PTY-capable login
environment. This image includes:

- default login user `exedev`
- PTY-capable shell environment
- OpenSSH server for local testing and platforms that expect port 22
- Shelley coding agent on port 9999
- long-running PID 1
- port 80 health page for exe.dev HTTPS proxy detection
- Nix CLI in PATH with flakes enabled

## Build

```sh
nix build .#image
```

The result is a Docker archive:

```sh
ls -lh result
```

## Use with exe.dev

After the GitHub Actions publish workflow has pushed `latest`:

```sh
ssh exe.dev new --image=ghcr.io/johnrichardrinehart/exe.dev-nixos:latest
```

Then SSH into the created VM:

```sh
ssh exedev@VM_NAME.exe.xyz
```

## Local Smoke Test

On a Docker-capable host:

```sh
docker load < result
docker run --rm -p 8080:80 exe-dev-nixos:latest
curl http://127.0.0.1:8080/
```

Shelley listens on port 9999 and requires the exe.dev auth proxy header for API
requests:

```sh
docker run --rm -p 9999:9999 exe-dev-nixos:latest
curl -H "X-Exedev-Userid: local" http://127.0.0.1:9999/api/models
```

For local SSH testing, pass your public key:

```sh
docker run --rm -p 2222:22 \
  -e "EXE_DEV_AUTHORIZED_KEYS=$(cat ~/.ssh/id_ed25519.pub)" \
  exe-dev-nixos:latest

ssh -p 2222 exedev@127.0.0.1
```

## CI

GitHub Actions builds the image on native free Linux runners for:

- `x86_64-linux` on `ubuntu-24.04`
- `aarch64-linux` on `ubuntu-24.04-arm`

The workflow uses Determinate Systems' Nix installer and Magic Nix Cache. On
pushes to `main`, it publishes architecture-specific images and a multi-arch
`latest` manifest to GHCR.
