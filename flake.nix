{
  description = "Session manager for the Lingmo desktop environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-filter.url = "github:numtide/nix-filter";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, nix-filter, crane, fenix }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        craneLib = crane.lib.${system}.overrideToolchain fenix.packages.${system}.stable.toolchain;

        pkgDef = {
          nativeBuildInputs = with pkgs; [ just pkg-config autoPatchelfHook ];
          buildInputs = with pkgs; [
            stdenv.cc.cc.lib
          ];
          src = nix-filter.lib.filter {
            root = ./.;
            include = [
              ./src
              ./Cargo.toml
              ./Cargo.lock
              ./Justfile
              ./data
            ];
          };
        };

        cargoArtifacts = craneLib.buildDepsOnly pkgDef;
        lingmo-session = craneLib.buildPackage (pkgDef // {
          inherit cargoArtifacts;
        });
      in {
        checks = {
          inherit lingmo-session;
        };

        packages.default = lingmo-session.overrideAttrs (oldAttrs: rec {
        buildPhase = ''
            just prefix=$out xdp_cosmic=/run/current-system/sw/bin/xdg-desktop-portal-lingmo build 
          '';
        installPhase = ''
            runHook preInstallPhase
            just prefix=$out install
          '';
        preInstallPhase = ''
            substituteInPlace data/start-lingmo --replace '#!/bin/bash' "#!${pkgs.bash}/bin/bash"
            substituteInPlace data/start-lingmo --replace '/usr/bin/lingmo-session' "${placeholder "out"}/bin/lingmo-session"
            substituteInPlace data/start-lingmo --replace '/usr/bin/dbus-run-session' "${pkgs.dbus}/bin/dbus-run-session"
            substituteInPlace data/lingmo.desktop --replace '/usr/bin/start-lingmo' "${placeholder "out"}/bin/start-lingmo"
        '';  
          passthru.providedSessions = [ "lingmo" ];
        });

        apps.default = flake-utils.lib.mkApp {
          drv = lingmo-session;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = builtins.attrValues self.checks.${system};
        };
      });

  nixConfig = {
    # Cache for the Rust toolchain in fenix
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
  };
}
