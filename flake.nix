{
  description = "Worktrunk integration for Emacs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    keg.url = "github:conao3/keg.el";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-darwin"];

      imports = [inputs.treefmt-nix.flakeModule];

      perSystem = {system, ...}: let
        overlay = _: prev: let
          emacs = prev.emacs30;
        in {
          inherit emacs;
        };
        pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [overlay];
        };
      in {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.emacs
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
