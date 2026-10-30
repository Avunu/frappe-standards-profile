{
  description = "Avunu's app-standards profile for frappe-nix: the frappe-nix this profile is validated against";

  # This repository is data (profile.toml, fleet.json), not a flake apps consume: apps read
  # it as a `flake = false` input named standards-profile. The flake only pins the
  # frappe-nix whose `frappe-nix profile validate` and fixture app the CI uses, so every
  # validate run is reproducible and Dependabot's `nix` entry moves the pin in a PR.
  #
  # It pins the release named by profile.toml's `requires-frappe-nix` lower bound, and the
  # validate workflow's `latest` job covers the newest release the range allows.
  inputs = {
    frappe-nix.url = "github:Avunu/frappe-nix/v1.1.0";
    nixpkgs.follows = "frappe-nix/nixpkgs";
  };

  outputs =
    { frappe-nix, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system} system);
    in
    {
      # The pinned frappe-nix source tree: its fixture app is what resolved.snapshot.json
      # is computed from (`nix eval --raw .#lib.frappe-nix-src`).
      lib.frappe-nix-src = "${frappe-nix}";

      packages = forAllSystems (
        _: system: {
          inherit (frappe-nix.packages.${system}) frappe-nix;
          default = frappe-nix.packages.${system}.frappe-nix;
        }
      );

      # `nix develop`: the pinned frappe-nix CLI, plus the tools the validate workflow uses.
      devShells = forAllSystems (
        pkgs: system: {
          default = pkgs.mkShell {
            packages = [
              frappe-nix.packages.${system}.frappe-nix
              pkgs.actionlint
              pkgs.jq
              pkgs.nixfmt
              pkgs.ruff
              pkgs.shellcheck
              pkgs.zizmor
            ];
          };
        }
      );

      formatter = forAllSystems (pkgs: _: pkgs.nixfmt);
    };
}
