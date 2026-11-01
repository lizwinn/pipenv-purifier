# SPDX-License-Identifier: MIT
#
# The default package overlay. It adds the packages of pkgs/ under
# `pkgs.pipenv-purifier` (`.cli`), and the builder `pkgs.buildPipenvProject`
# (nix/lib/build-pipenv-project.nix) beside them, where nixpkgs keeps its own
# builders, so a package written for callPackage takes it by name. A
# consumer that lists this flake in `projects` holds it as
# `pipenv-purifier/default`, which its package sets apply by default.
{ closure-lib, ... }:
let
  packages = closure-lib.caisson.nixpkgs.mkPackagesOverlay ../../pkgs "pipenv-purifier";
in
{
  overlay =
    final: prev:
    packages final prev
    // {
      buildPipenvProject = final.callPackage ../../nix/lib/build-pipenv-project.nix { };
    };
}
