{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    flake-utils,
    nixpkgs,
  }: let
    orangepi-r1-plus-lts-config = nixpkgs.lib.nixosSystem {
      modules = [
        ./config.nix
        ./sd-image-aarch64-orangepi-r1plus.nix
        ./sd-image.nix
      ];
      system = "aarch64-linux";
    };
  in
    (flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      packages.default = orangepi-r1-plus-lts-config.config.system.build.sdImage;
      formatter = pkgs.alejandra;
      devShells.default = pkgs.mkShell {
        packages = [pkgs.nixos-rebuild];
      };
    }))
    // {
      nixosConfigurations.orangepi-r1-plus-lts-config = orangepi-r1-plus-lts-config;
    };
}
