{
  description = "subha279 Sunflower Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:danth/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    apple-fonts = {
      url = "github:Lyndeno/apple-fonts.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      stylix,
      apple-fonts,
      zen-browser,
      ...
    }:
    let
      vars = import ./lib/variables.nix;
    in
    {
      nixosConfigurations = {
        sunflower = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          specialArgs = {
            inherit vars;
            inherit inputs;
          };

          modules = [
            {
              nixpkgs.overlays = [
                apple-fonts.overlays.default

                (final: prev: {
                  zen-browser = zen-browser.packages.${final.stdenv.hostPlatform.system}.default;
                  opencode = nixpkgs-unstable.legacyPackages.${final.stdenv.hostPlatform.system}.opencode;
                })
              ];
            }

            stylix.nixosModules.stylix
            ./hosts/sunflower

            home-manager.nixosModules.home-manager

            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = {
                inherit vars;
                inherit inputs;
              };
              home-manager.users.${vars.user.username} = import ./home;
            }
          ];
        };
      };
    };
}
