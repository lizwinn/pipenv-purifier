# SPDX-License-Identifier: MIT
{ closure-lib, ... }:
{
  config,
  inputs,
  lib,
  ...
}:
{

  imports = [
    inputs.flake-parts.flakeModules.partitions
    closure-lib.caisson.modules.flake."purifier/purifier-packages"
  ];

  # The flake publishes the derivations of the scope `pkgs.pipenv-purifier`
  # as its packages.
  purifier.scope = "pipenv-purifier";

  debug = false;
  # The package overlay registry (pkg-overlays/) has the `default` entry,
  # which the package set applies by default, and which the flake exports as
  # `pkgOverlays` and as the plain `overlays.default`.
  caisson.libOverlays.exported = libOverlays: {
    inherit (libOverlays) default;
  };

  # `nix run github:nix-purifiers/pipenv-purifier -- lock` writes
  # pipenv-purifier.lock.json for the Pipenv project in the current
  # directory. `nix develop github:nix-purifiers/pipenv-purifier` gives the
  # Pipenv that the Nix builds run, with the CLI.
  perSystem =
    { config, pkgs, ... }:
    {
      packages.default = config.packages.cli;
      devShells.default = pkgs.mkShell {
        packages = [
          pkgs.pipenv
          config.packages.cli
        ];
      };
    };

  partitionedAttrs.checks = "checks";
  partitionedAttrs.formatter = "formatter";

  partitions.formatter = {
    extraInputs = (lib.caisson.pins.flake-compat ../../../tests/dependencies).sources;
    module =
      { inputs, ... }:
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        perSystem.treefmt.programs.nixfmt.enable = true;
      };
  };

  partitions.checks = {
    extraInputs = (lib.caisson.pins.flake-compat ../../../tests/dependencies).sources;
    module =
      { inputs, self, ... }:
      {
        imports = [ inputs.treefmt-nix.flakeModule ];
        perSystem =
          { pkgs, system, ... }:
          {
            checks = import ../../../tests {
              inherit pkgs;
              overlay = self.overlays.default;
              inherit (self.packages.${system}) cli;
              inherit (self.lib) purifier;
            };
            treefmt.programs.nixfmt.enable = true;
          };
      };
  };

}
