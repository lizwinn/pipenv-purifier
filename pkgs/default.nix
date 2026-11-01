# SPDX-License-Identifier: MIT
{ callPackage, ... }:
{
  # The `pipenv-purifier` command: `lock` writes pipenv-purifier.lock.json,
  # `sync` installs the project's .venv offline, and `publish` uploads what
  # the Nix build of a local package made. The default package overlay
  # gives it the source of the shared purifier library.
  cli = callPackage ./cli {
    purifierSource = throw "pipenv-purifier: the CLI takes the purifier library from the default package overlay";
  };
}
