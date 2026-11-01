# Design

## Two lockfiles

Pipfile.lock pins every package of every category with the SHA-256 hashes
of all of the release's files, for every platform. It names packages from git
by repository and commit, packages from a URL by the URL, and local packages
by path. It records no URL of a file from an index, no build requirement,
and nothing about what the local packages produce. The Nix library reads
Pipfile.lock with `builtins.fromJSON` (`nix/lib/lock.nix`).

`pipenv-purifier lock` (`src/pipenv_purifier.py`) writes
`pipenv-purifier.lock.json` with what Pipfile.lock leaves out:

- `artifacts`: download entries of the shared purifier library. A file from
  an index or a URL is a file entry: `path` (the file name, or
  `file/<name>` for a URL), `url`, `mirrors` and an SRI `hash`. A git
  checkout is a git entry: `path` (`git/<name>-<commit>`), `git` with `url`,
  `rev`, `submodules`, `leaveDotGit` and `commitObject`, and the NAR `hash`
  that `nix-prefetch-git` reports. The build makes a wheel of the checkout
  and needs no `.git`, so `leaveDotGit` is false and `commitObject` null.
- `packages`: for each package of an index, `"<name>==<version>"`, the file
  names of its wheels and of its sdist.
- `buildRequirements`: each distinct set of build requirements, with the
  keys of the packages `pipenv lock` resolved it to. A set that did not
  resolve has `error` instead, and the Nix build reports it only if it has
  to build a package that needs it.
- `builds`: for each package that may be built, the index of its set.
- `sources`: for each package from git or a URL, its artifact and, for git,
  the version its backend read from the repository.
- `outputs`: for each local package inside the project, its path, version,
  sdist and wheel names, whether the wheel is pure, and its scripts.
- `inputsHash`: a hash over Pipfile.lock and the `pyproject.toml` of every
  local package inside the project. The Nix library computes the same hash
  and refuses the lockfile when they differ.

## The lock run

1. `pipenv verify` checks that Pipfile.lock matches the Pipfile.
2. For each package of an index, the tool reads the package's page on its
   index, as JSON (PEP 691) or HTML (PEP 503), and keeps the files whose
   SHA-256 Pipfile.lock lists. The URLs it records carry no credentials.
3. For each package that may have to be built on some system (an sdist and
   no wheel tagged `none-any`), each local package, git checkout and source
   archive, the tool reads the static build requirements of the source
   tree's `[build-system]` table and asks the backend for the requirements
   it adds, through the PEP 517 hooks `get_requires_for_build_sdist`,
   `get_requires_for_build_wheel` and `get_requires_for_build_editable`.
4. It resolves each distinct set with `pipenv lock` on a throwaway Pipfile
   that reads the project's indexes, then reads the files of the resolved
   packages as in step 2, and repeats step 3 for those that may have to be
   built.
5. It builds each local package inside the project with `python -m build`
   and records its outputs.

## Choosing the files for a system

The shared [purifier](https://github.com/nix-purifiers/purifier) library's
`wheels` decides from a wheel's file name whether it installs with the
build's Python on the build's system (PEP 425 tags, manylinux 1, 2010, 2014
and `2_N` against the glibc of the package set, `abi3`). For each package,
`nix/lib/build-pipenv-project.nix` takes its wheels that install, or else
its sdist and the build of it. A build adds the files of its set of build
requirements, chosen the same way, and the builds those need in turn. The
library's `fetchEntry` fetches every chosen file and every git checkout, and
the files are linked into one flat directory, the wheelhouse.

## Installing in the sandbox

pip runs with `PIP_NO_INDEX` and `PIP_FIND_LINKS` pointing at the
wheelhouse, so it reads nothing else, and its build isolation installs build
requirements from the wheelhouse too.

The build rewrites a copy of Pipfile.lock: a package from a URL becomes a
path to its locked file, a package from git a path to its wheel, and a local
package a path into the build's copy of the project, or into the build's copy
of what `pathSources` gives for a path outside it. Each installs as a copy,
because the result outlives the build directory. Pipenv then runs `pipenv
sync --categories ...` with `PIPENV_PIPFILE` pointing at the copy and
`VIRTUAL_ENV` at the output, a virtual environment of the build's Python.

A package from git builds into a wheel in a derivation of its own, with
`SETUPTOOLS_SCM_PRETEND_VERSION` set to the version the lock run read from
the repository. The locked checkout has no `.git`, and setuptools-scm, which
hatch-vcs uses, cannot apply its per-distribution variable before it knows
the distribution's name, so the variable has to apply to that build alone.

A local package's sdist and wheel come from `python -m build`, which builds
in an isolated environment that pip fills from the wheelhouse. The build
checks that it made the files the lockfile names.

## The interpreter

The Python comes from nixpkgs: `pythonXY` for the Pipfile's
`python_version`, or the `python` argument. Pipenv never downloads one.
