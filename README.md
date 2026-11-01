# pipenv-purifier

pipenv-purifier lets Nix build a [Pipenv](https://pipenv.pypa.io/) project in
its sandbox, offline, from the project's lockfiles. You do not commit
generated Nix files to the project.

Pipfile.lock already pins every package with the hashes of all of its files.
It leaves out three things: the URLs of those files, the build requirements
of the packages that have to be built (local packages, git checkouts and
sdists), and what the project's local packages produce. `pipenv-purifier
lock` adds them in `pipenv-purifier.lock.json` beside Pipfile.lock. Pipenv
itself installs the project, in the Nix sandbox and on your machine, from the
locked files and nothing else.

The design follows [sbt-nix-backend](https://github.com/clhodapp/sbt-nix-backend),
which is part of the [nix-purifiers](https://nix-purifiers.github.io) family.

## Lock

From the directory that holds the Pipfile:

```zsh
nix run github:nix-purifiers/pipenv-purifier -- lock
```

Pipfile.lock has to exist and match the Pipfile. Commit
`pipenv-purifier.lock.json`, and run the command again whenever Pipfile.lock
or the `pyproject.toml` of a local package changes. The Nix build refuses a
`pipenv-purifier.lock.json` that no longer matches them.

The command looks up the URL of every hash in Pipfile.lock on the package's
index, for every platform. It reads the build requirements of each package
that may have to be built through the build backend's PEP 517 hooks, and
resolves each set with `pipenv lock` on a throwaway Pipfile that reads the
project's indexes. It fetches each git dependency at its locked commit, and
records the version that its backend reads from git. It builds each local
package once, to record the names of its sdist and wheel and the scripts it
installs.

## Build

The flake's `overlays.default` adds `buildPipenvProject` to a package set:

```nix
{
  inputs.pipenv-purifier.url = "github:nix-purifiers/pipenv-purifier";
  inputs.nixpkgs.follows = "pipenv-purifier/nixpkgs";

  outputs = { nixpkgs, pipenv-purifier, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ pipenv-purifier.overlays.default ];
      };
      project = pkgs.buildPipenvProject { src = ./.; };
    in
    {
      # A virtual environment with the packages of the `default` category.
      packages.${system}.default = project.environment;
      # The sdist and wheel of the local package `app`.
      packages.${system}.app-dist = project.packages.app;
      # The script `app`, for `nix run`.
      apps.${system}.default = {
        type = "app";
        program = pkgs.lib.getExe project.programs.app;
      };
    };
}
```

`buildPipenvProject` gives:

- `environment`: a virtual environment with the packages of `categories`,
  installed by `pipenv sync`, with their scripts in `bin/`.
- `packages.<name>`: for each local package of the project, a package that
  Pipfile.lock names by a path inside the project, its sdist and wheel. Its
  `artifacts` attribute names the files without building them:
  `artifacts.sdist`, `artifacts.wheel`, and each file by its name, such as
  `artifacts."app-1.0.0.tar.gz"`.
- `programs.<script>`: each script of the local packages, from
  `environment`, as a package with `meta.mainProgram`.

Every name in `packages`, `artifacts` and `programs` comes from the lockfile,
so Nix knows them without building anything.

`buildPipenvProject` takes these arguments:

- `src`: the project root.
- `categories`: the package categories `environment` installs, as `pipenv
  sync --categories`. The default is `[ "default" ]`.
- `python`: the interpreter. The default is nixpkgs' `pythonXY` for the
  `python_version` in the Pipfile's `[requires]`, or `python3`.
- `fetchurl`: a replacement for nixpkgs' `fetchurl` for the locked files,
  for credentials or mirrors. It takes the arguments that the
  [purifier](https://github.com/nix-purifiers/purifier) library's
  `fetchEntry` passes to `fetchurl`.
- `pathSources`: the local packages that Pipfile.lock names by a path
  outside `src`, such as `"../shared"`, each mapped to a Nix path.

For each package, the build fetches the wheels that install with that
Python on the build's system. When no wheel installs, it fetches the sdist
and the build requirements that building it needs. One lockfile serves
every Linux system. A package from git becomes a wheel in a derivation of
its own, so that a backend reading its version from git gets the version
the lock run recorded.

## Interactive use

```zsh
nix run github:nix-purifiers/pipenv-purifier -- sync
```

`sync` has Nix fetch the locked files for this machine and runs `pipenv
sync --dev` into the project's `.venv`, offline. Local packages stay
editable when Pipfile.lock says so. Pipenv finds the `.venv` afterwards, so
`pipenv run` and `pipenv shell` work as usual. `--categories` picks other
categories.

## Publish

```zsh
nix run github:nix-purifiers/pipenv-purifier -- publish -- --token "$PYPI_TOKEN"
```

`publish` builds each local package with Nix and uploads what Nix built with
`uv publish`. Arguments after `--` go to `uv publish`. `--package <name>`
limits it to some packages, and `--dist <path>` uploads a package that Nix
built before instead of building. Pipenv has no upload command. The twine of
nixpkgs, 6.2, refuses metadata version 2.5, which current build backends
such as hatchling write, so the upload goes through uv.

## Limits

- The build runs on Linux (x86_64 and aarch64).
- A package with neither a wheel that installs on the build's system nor
  an sdist is left out of the wheelhouse. Its markers leave it out on that
  system when it is a package for another platform. When its markers do
  include it, pip fails on the missing file.

`docs/development/` describes the design and the tests.

The purifier idea was inspired by nixcloud's
[cargo (libnix)](https://github.com/nixcloud/cargo).
