# SPDX-License-Identifier: MIT
{ callPackage, ... }:
{
  # The `pipenv-purifier` command: `lock` writes pipenv-purifier.lock.json,
  # `prefetch` fetches what the development loop needs and installs the
  # project's .venv offline, and `publish` uploads the release that Nix
  # built. The default package overlay gives it the source of the shared
  # purifier library.
  cli = callPackage ./cli {
    purifierSource = throw "pipenv-purifier: the CLI takes the purifier library from the default package overlay";
  };
}
