# SPDX-License-Identifier: MIT
#
# The `pipenv-purifier` library namespace, with the two functions of the
# purifier contract. `buildPipenvProject` (nix/lib/build-pipenv-project.nix)
# takes the package set to build with as `pkgs`, and builds with the shared
# purifier library of the composed library, `lib.purifier`. `readLock`
# (nix/lib/lock.nix) reads a project's lockfiles into the lock in memory.
{ ... }:
{

  overlay = final: prev: {
    pipenv-purifier = (prev.pipenv-purifier or { }) // {
      buildPipenvProject = import ../../nix/lib/build-pipenv-project.nix {
        lib = final;
        inherit (final) purifier;
      };
      readLock = import ../../nix/lib/lock.nix;
    };
  };

}
