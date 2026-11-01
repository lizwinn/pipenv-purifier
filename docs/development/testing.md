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
- `sync-stale-pipfile` adds a package to the Pipfile by hand and checks
  that `sync` refuses before installing, naming `pipenv lock` and
  `pipenv-purifier lock`.
- `lock-run` runs `pipenv lock` and `pipenv-purifier lock` on a copy of the
  simple fixture against a local index that serves the fixture's locked
  files. It checks that a second lock run writes the same bytes, and that
  the lockfile is the committed one byte for byte once each URL is the
  committed URL of the same file.
- `publish` uploads the simple fixture's package to a local index with
  `pipenv-purifier publish --dist`.
- `nix-library` tests wheel selection and name and path normalization. It
  also tests that the library refuses a stale lockfile, a tampered hash, a
  package or download entry missing from the lockfile, a JSON file that is
  no lockfile, and another format version.
- `unit` runs `tests/test_pipenv_purifier.py`, the unit tests of the lock
  tool: names, file names and URLs, JSON and HTML index pages, the
  throwaway Pipfile of build requirements, the rewritten Pipfile.lock of
  `sync`, the scripts of a wheel, the inputs hash, and a missing or damaged
  Pipfile.lock.

CI runs the checks on x86_64-linux and aarch64-linux.

`tests/relock-fixtures.sh` relocks every fixture against PyPI and GitHub
with the Pipenv and Python of the flake's package set.
