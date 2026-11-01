# Testing

```zsh
nix flake check
```

The checks (`tests/default.nix`) build in the sandbox, with no network
access other than the fixed-output fetches of locked files:

- `simple`, `simple-program`, `simple-categories` and `simple-package` build
  `tests/fixtures/simple`: a hatchling project, installed from its own
  directory, with attrs (a wheel), docopt (an sdist that the locked
  setuptools builds) and markupsafe (wheels for each CPU) in `default`, six
  in `develop`, and iniconfig in the custom category `tools`.
- `sources` builds `tests/fixtures/sources`, with a package of every kind
  besides an index: attrs from git (hatch-vcs), six from a GitHub archive
  URL, a local directory, a local sdist and a local wheel.
- `outside` builds `tests/fixtures/outside/app`, which depends on a path
  outside its directory through `pathSources`.
- `sync-simple` and `sync-sources` run `pipenv-purifier sync` on copies of
  the fixtures, then edit the project and check that the editable install
  sees the edit.
- `lock-run` runs `pipenv lock` and `pipenv-purifier lock` on a copy of the
  simple fixture against a local index that serves the fixture's locked
  files, and compares the result with the committed lockfile, apart from the
  URLs.
- `publish` uploads the simple fixture's package to a local index with
  `pipenv-purifier publish --dist`.
- `nix-library` tests wheel selection, name and path normalization, and the
  refusal of a stale lockfile.

CI runs the checks on x86_64-linux and aarch64-linux.

`tests/relock-fixtures.sh` relocks every fixture against PyPI and GitHub
with the Pipenv and Python of the flake's package set.
