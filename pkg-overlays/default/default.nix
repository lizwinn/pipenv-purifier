# SPDX-License-Identifier: MIT
#
# The default package overlay. It adds the packages of pkgs/ under
# `pkgs.pipenv-purifier` (`.cli`), and the builder `pkgs.buildPipenvProject`
# (nix/lib/build-pipenv-project.nix) beside them, where nixpkgs keeps its own
# builders, so a package written for callPackage takes it by name. A
# consumer that lists this flake in `projects` holds it as
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
