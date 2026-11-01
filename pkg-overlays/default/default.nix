# SPDX-License-Identifier: MIT
#
# The default package overlay. It adds the packages of pkgs/ under
# `pkgs.pipenv-purifier` (`.cli`). A consumer that lists this flake in
# `projects` holds it as `pipenv-purifier/default`, which its package sets
# apply by default.
#
# The CLI takes the source of the shared purifier library from this flake's
# closure, because the CLI's own Nix builds import it.
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
    };
}
