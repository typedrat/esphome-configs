{
  description = "Description for the project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-root.url = "github:srid/flake-root";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    esphome = {
      url = "github:esphome/esphome/2026.9.0";
      flake = false;
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.devshell.flakeModule
        inputs.flake-root.flakeModule
        inputs.treefmt-nix.flakeModule
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      perSystem = {
        config,
        pkgs,
        ...
      }: let
        # nixpkgs' esphome with its source swapped for the `esphome` input.
        # Dependencies come from the derivation's own Python set so they agree
        # with its package overrides (e.g. paho-mqtt 1.x).
        esphome = pkgs.esphome.overridePythonAttrs (old: let
          py = (builtins.head old.dependencies).pythonModule.pkgs;
          version = builtins.head (builtins.match ''.*__version__ = "([^"]+)".*'' (builtins.readFile "${inputs.esphome}/esphome/const.py"));
        in {
          inherit version;
          src = inputs.esphome;

          # Run the platformio and esptool binaries directly: both live outside
          # esphome's Python env.
          patches = [
            ./nix/esphome-esp32-post-build-esptool-reference.patch
            ./nix/esphome-platformio-binary-reference.patch
          ];

          postPatch = ''
            sed -i -E \
              -e 's/"setuptools==[^"]*"/"setuptools"/' \
              -e 's/"wheel[^"]*"/"wheel"/' \
              pyproject.toml
          '';

          dependencies =
            old.dependencies
            ++ (with py; [
              aiohappyeyeballs
              ninja
            ]);

          # nixpkgs' disabled-test list is written for its own, older release.
          doCheck = false;

          meta = old.meta // {changelog = "https://github.com/esphome/esphome/releases/tag/${version}";};
        });
      in {
        treefmt.config = {
          inherit (config.flake-root) projectRootFile;
          package = pkgs.treefmt;

          programs = {
            # Nix
            alejandra.enable = true;
            deadnix.enable = true;
            statix.enable = true;

            # YAML
            prettier.enable = true;
          };
        };

        devshells.default = {
          packages = [
            esphome
            pkgs.minicom
            pkgs.sops
          ];
        };

        formatter = config.treefmt.build.wrapper;
      };
    };
}
