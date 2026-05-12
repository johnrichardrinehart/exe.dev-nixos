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
          image = import ./image.nix { inherit pkgs nixSource; };
        in
        {
          default = image;
          image = image;
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
