{
  description = "Worktrunk integration for Emacs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    keg.url = "github:conao3/keg.el";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-darwin"];

      imports = [inputs.treefmt-nix.flakeModule];

      perSystem = {
        pkgs,
        system,
        ...
      }: let
        emacs = pkgs.emacs31;
      in {
        devShells.default = pkgs.mkShell {
          packages = [
            emacs
            pkgs.gnumake
            inputs.keg.packages.${system}.default
          ];
        };

        treefmt = {
          programs.alejandra.enable = true;
        };
      };
    };
}
