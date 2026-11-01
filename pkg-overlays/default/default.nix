# SPDX-License-Identifier: MIT
#
# The default package overlay, which the flake exports as
# `overlays.default`. It adds the packages of pkgs/ under
# `pkgs.pipenv-purifier` (`.cli`), and the builder `buildPipenvProject`
# (nix/lib/build-pipenv-project.nix) beside them, where nixpkgs keeps its own
# builders. A package takes the builder by name, as
# `{ buildPipenvProject }: (buildPipenvProject { src = ./.; }).packages.app`.
# A consumer that lists this flake in `projects` holds the overlay as
# `pipenv-purifier/default`, which its package sets apply by default.
#
# Both take the shared purifier library from this flake's closure: the
# builder its functions, and the CLI its source, which the CLI's own Nix
# builds import.
{ closure-lib, closure-inputs, ... }:
let
  packages = closure-lib.caisson.nixpkgs.mkPackagesOverlay ../../pkgs "pipenv-purifier";
in
{
  overlay =
    final: prev:
    let
      base = packages final prev;
    in
    base
    // {
      pipenv-purifier = base.pipenv-purifier // {
        cli = base.pipenv-purifier.cli.override { purifierSource = closure-inputs.purifier; };
      };
      buildPipenvProject = final.callPackage ../../nix/lib/build-pipenv-project.nix {
        inherit (closure-lib) purifier;
      };
    };
}
