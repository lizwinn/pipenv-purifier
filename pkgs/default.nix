# SPDX-License-Identifier: MIT
{ callPackage, ... }:
{
  # The `pipenv-purifier` command: `lock` writes pipenv-purifier.lock.json,
  # `sync` installs the project's .venv offline, and `publish` uploads what
  # the Nix build of a local package made.
  cli = callPackage ./cli { };
}
