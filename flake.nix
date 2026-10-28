{
  description = "Claude Desktop (official Anthropic app) for Arch, CachyOS and NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
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
              config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "claude-desktop";
            }
          )
        );
    in
    {
      packages = forAllSystems (pkgs: rec {
        claude-desktop = pkgs.callPackage ./nix/package.nix { };
        default = claude-desktop;
      });

      overlays.default = final: _prev: {
        claude-desktop = final.callPackage ./nix/package.nix { };
      };

      nixosModules.default = import ./nix/module.nix self;
    };
}
