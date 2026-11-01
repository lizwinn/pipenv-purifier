# pipenv-purifier

pipenv-purifier lets Nix build a [Pipenv](https://pipenv.pypa.io/) project in
its sandbox, offline, from the project's lockfiles. You do not commit
generated Nix files to the project.

Pipfile.lock already pins every package with the hashes of all of its files.
It leaves out the URLs of those files, the build requirements of the
packages that have to be built (local packages, git checkouts and sdists),
the content hash of a git checkout, and the names of what the local
packages produce. `pipenv-purifier lock` records only those, in
`pipenv-purifier.lock.json` beside Pipfile.lock. Pipenv itself installs the
project, in the Nix sandbox and on your machine, from the locked files and
nothing else.

pipenv-purifier is part of the [nix-purifiers](https://nix-purifiers.github.io)
family and meets the family's
[contract](https://github.com/nix-purifiers/purifier/blob/main/CONTRACT.md).

## Quickstart

A project starts with three commands, which run in the directory that holds
the Pipfile.

```zsh
nix run github:nix-purifiers/pipenv-purifier -- lock
nix run github:nix-purifiers/pipenv-purifier -- prefetch
pipenv run pytest
```

`lock` writes `pipenv-purifier.lock.json`. It also writes Pipfile.lock when
the project has none, and you commit both files. `prefetch` has Nix fetch
everything the project needs on this machine, and it installs the
project's `.venv` from those files, offline. After that, the everyday
Pipenv commands work.

To build the project with Nix, a flake calls the builder of this flake's
library:

```nix
{
  inputs.pipenv-purifier.url = "github:nix-purifiers/pipenv-purifier";
  inputs.nixpkgs.follows = "pipenv-purifier/nixpkgs";

  outputs = { nixpkgs, pipenv-purifier, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      project = pipenv-purifier.lib.pipenv-purifier.buildPipenvProject {
        inherit pkgs;
        src = ./.;
      };
    in
    {
      # The sdist and wheel of the local package `app`.
      packages.${system}.app = project.packages.app;
      # A virtual environment with the packages of the `default` category.
      packages.${system}.environment = project.environment;
      # The Pipfile's script `test`, run in the sandbox.
      checks.${system}.tests = project.tests;
      # The script `app`, for `nix run`.
      apps.${system}.default = {
        type = "app";
        program = pkgs.lib.getExe project.programs.app;
      };
    };
}
```

`buildPipenvProject` gives:

- `packages.<name>`: for each local package of the project, a package that
  Pipfile.lock names by a path of a directory inside the project, its sdist
  and wheel. Its `artifacts` attribute names the files without building
  them: `artifacts.sdist`, `artifacts.wheel`, and each file by its name,
  such as `artifacts."app-1.0.0.tar.gz"`.
- `tests`: the Pipfile's script `test` (under `[scripts]`), run by the shell
  in the sandbox, in a writable copy of an environment with the packages of
  every category.
- `release`: the sdists and wheels of every local package in one directory,
  which `pipenv-purifier publish` uploads.
- `fetches`: every download of the lock, as entries of the shared
  [purifier](https://github.com/nix-purifiers/purifier) library. A wheel for
  some systems only carries them in `systems`.
- `environment`: a virtual environment with the packages of `categories`,
  installed by `pipenv sync`, with their scripts in `bin/`.
- `programs.<script>`: each script of the local packages, from
  `environment`, as a package with `meta.mainProgram`.
- `prefetch`: what `pipenv-purifier prefetch` installs the `.venv` from.

Every attribute name comes from the lockfiles, so Nix knows them without
building anything.

`buildPipenvProject` takes these arguments:

- `pkgs`: the package set to build with.
- `src`: the project root, which holds the Pipfile.
- `fetchers`: replacements for the fetchers of nixpkgs, which the purifier
  library's `fetchEntry` takes. A `fetchurl` that sends credentials or reads
  a company mirror goes here.
- `lockFile`: the lockfile, by default `src + "/pipenv-purifier.lock.json"`.
  It may lie outside `src`, as in a flake that packages a project without
  changing it.
- `categories`: the package categories `environment` installs, as `pipenv
  sync --categories`. The default is `[ "default" ]`.
- `testScript` and `testCategories`: the script `tests` runs, by default
  `"test"`, and the categories it runs with, by default all of them.
- `python`: the interpreter. The default is nixpkgs' `pythonXY` for the
  `python_version` in the Pipfile's `[requires]`, or `python3`.
- `pathSources`: the local packages that Pipfile.lock names by a path
  outside `src`, such as `"../shared"`, each mapped to a Nix path.

`lib.pipenv-purifier.readLock { src, lockFile }` reads the two
lockfiles into the lock in memory of the contract, `{ purifier, entries,
outputs, problems }`, for a tool such as an SBOM generator.

## Everyday loop

The everyday loop is Pipenv's own: `pipenv run`, `pipenv shell`, and the
tests in the `.venv` that `prefetch` installed. Local packages stay editable
when Pipfile.lock says so, so an edit to the source shows at once.

To add a dependency, run `pipenv install <package>` (or edit the Pipfile and
run `pipenv lock`), then `pipenv-purifier lock`, then `pipenv-purifier
prefetch`. Run `pipenv-purifier lock` again whenever Pipfile.lock or the
`pyproject.toml` of a local package changes. The Nix build and `prefetch`
refuse a lockfile that no longer matches them.

To update dependencies, run `pipenv-purifier update`, which re-resolves
every package with `pipenv lock`, or `pipenv-purifier update <package>...`,
which re-resolves the named ones with `pipenv upgrade`. It then relocks
`pipenv-purifier.lock.json` against the new Pipfile.lock. `lock` keeps
Pipfile.lock as it is.

`pipenv-purifier lock` keeps Pipfile.lock as Pipenv resolved it. When
Pipfile.lock is missing or no longer matches the Pipfile, `lock` writes it
with `pipenv lock` first. It looks up the URL of every hash of Pipfile.lock
on the package's index, for every platform. It reads the build requirements of
each package that may have to be built through the build backend's PEP 517
hooks, and resolves each set with `pipenv lock` on a throwaway Pipfile, at
the versions Pipfile.lock pins wherever the set allows them. It fetches each
git dependency at its locked commit and records the version that its
backend reads from git. It builds each local package once, to record the
names of its sdist and wheel and the scripts it installs. `--lockfile
<path>` writes the lockfile somewhere else, and every other command takes
the same option.

## Offline work

`pipenv-purifier prefetch` realizes in the Nix store the Python of the
build and the locked files of every category for this system, development
and test packages included, with the wheels of the packages from git. It
keeps them alive with a garbage-collector root at
`.pipenv-purifier/inputs` in the project, which belongs in `.gitignore`.
Then it runs `pipenv sync --dev` into `.venv` with pip reading those files
and nothing else. `--categories` picks other categories.

After a prefetch, `pipenv run`, `pipenv shell`, the tests and the editor
work with the network cut off. `pipenv install`, `pipenv lock` and
`pipenv-purifier update` need the network, as they resolve against the
index.

## Editor

An editor for Python needs the interpreter of the `.venv`, with the
project's packages in it. Point the editor's Python at `.venv/bin/python`,
or let it find `.venv` in the project, as Pyright and the Python extension
of VS Code do. The language server itself comes from the editor's
installation, not from the project's lockfiles.

## Errors and fixes

| Error | Fix |
| --- | --- |
| `Pipfile.lock does not match the Pipfile`, from `prefetch` | Run `pipenv-purifier lock`, which runs `pipenv lock` first. |
| `pipenv-purifier.lock.json no longer matches Pipfile.lock` | Run `pipenv-purifier lock`. This follows a `pipenv install`. |
| `... was edited after pipenv-purifier lock wrote it` | Run `pipenv-purifier lock`. The lockfile's `contentHash` no longer matches its content. |
| `... does not agree with Pipfile.lock: it has no files of <package>` | Run `pipenv-purifier lock`. |
| `... is not a lockfile of this pipenv-purifier` or `has lock format version` | Run `pipenv-purifier lock` with this version of pipenv-purifier. |
| `has no pipenv-purifier.lock.json` | Run `pipenv-purifier lock`. |
| `... failed 3 times ...` during a lock | Check the network, and run `pipenv-purifier lock` again. |
| `the Pipfile has no script test` | Add `test` under `[scripts]`, or pass `testScript`. |
| `Pipfile.lock names the local path ../x, which is outside src` | Pass it in `pathSources`. |

## Sources supported and refused

Supported:

- Packages of the indexes of the Pipfile's `[[source]]` tables, read as JSON
  (PEP 691) or HTML (PEP 503) pages. The lockfile records no credentials. An
  index that needs them gets a `fetchurl` in `fetchers` that supplies them.
- Packages from git, pinned by Pipfile.lock to a commit, with submodules and
  with `subdirectory`. A backend that reads its version from git, such as
  setuptools-scm or hatch-vcs, gets the version the lock run read.
- Packages from a URL of a wheel, an sdist or a source archive.
- Local directories, sdists and wheels, editable or not, inside the project
  or, through `pathSources`, outside it.
- Every package category, `default`, `develop` and custom ones.

Refused:

- A git reference that is not a commit. Run `pipenv lock` again.
- A build requirement that names a URL. Build requirements come from an
  index.
- A URL of Pipfile.lock with credentials.
- A hash of another algorithm than sha256.

The builds run on Linux, x86_64 and aarch64. A package with neither a wheel
that installs on the build's system nor an sdist is left out of the
wheelhouse. Its markers leave it out on that system when it is a package
for another platform. When its markers do include it, pip fails on the
missing file.

## Examples

[Pipenv](https://github.com/pypa/pipenv) develops itself with a Pipfile, so
its repository is a Pipenv project like any other. A developer of Pipenv
works on a clone of it as the Quickstart shows:

```zsh
git clone https://github.com/pypa/pipenv
cd pipenv
nix run github:nix-purifiers/pipenv-purifier -- lock
nix run github:nix-purifiers/pipenv-purifier -- prefetch
pipenv run pytest tests/unit
```

A flake can also package Pipenv without changing its repository. The
lockfile then lives in the packaging flake, and `--lockfile` writes it
there from a clone of the revision the flake builds:

```zsh
cd pipenv
nix run github:nix-purifiers/pipenv-purifier -- lock --lockfile ../pipenv-packaging/pipenv-purifier.lock.json
```

The flake in `pipenv-packaging/` takes the repository as an input and
builds it from that lockfile:

```nix
{
  inputs.pipenv-purifier.url = "github:nix-purifiers/pipenv-purifier";
  inputs.nixpkgs.follows = "pipenv-purifier/nixpkgs";
  inputs.pipenv-src = {
    url = "github:pypa/pipenv";
    flake = false;
  };

  outputs = { nixpkgs, pipenv-purifier, pipenv-src, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      project = pipenv-purifier.lib.pipenv-purifier.buildPipenvProject {
        inherit pkgs;
        src = pipenv-src;
        lockFile = ./pipenv-purifier.lock.json;
        categories = [ "default" "develop" ];
      };
    in
    {
      # A virtual environment with the dependencies of Pipenv and its
      # development tools.
      packages.${system}.environment = project.environment;
    };
}
```

Pipenv's Pipfile does not list Pipenv itself as a local package, so
`project.packages` is empty for this repository. A project whose Pipfile
lists itself, as with `app = { path = ".", editable = true }`, gets its
sdist and wheel as `project.packages.app`.

When the flake moves `pipenv-src` to another revision, run the same `lock
--lockfile` command in a clone of that revision.

## Credits

The design follows [sbt-nix-backend](https://github.com/clhodapp/sbt-nix-backend).
The purifier idea was inspired by nixcloud's
[cargo (libnix)](https://github.com/nixcloud/cargo).
`docs/development/` describes the design and the tests.
