# Testing

```zsh
nix flake check
```

The checks (`tests/default.nix`) build in the sandbox, with no network
access other than the fixed-output fetches of locked files. A check that
needs a package index runs pypiserver on 127.0.0.1 in the sandbox.

The conformance checks of the purifier contract:

- `conformance-stale` changes Pipfile.lock, as after `pipenv install`.
- `conformance-tampered` edits the lockfile, which its `contentHash` finds,
  and records a URL under a hash that neither lockfile lists, with the
  `contentHash` written again.
- `conformance-missing` removes the lockfile, the URLs of a package that
  Pipfile.lock pins, and the hashes of the packages that only build
  requirements need.
- `conformance-malformed` writes a file that is not JSON, JSON that is no
  lockfile, and another format version.
- `conformance-relock` runs `pipenv lock` and `pipenv-purifier lock` on a
  copy of the simple fixture against a local index that serves its locked
  files. A second lock run writes the same bytes, `--lockfile` writes the
  same bytes elsewhere, and the lockfile is the committed one byte for byte
  once the URLs and the two hashes that depend on them are the committed
  ones.
- `conformance-rebuild` builds the simple fixture's sdist and wheel twice
  and compares the bytes.
- `conformance-offline` runs `prefetch` on a copy of the simple fixture,
  edits the editable package, and runs `pipenv run simple` and `pipenv run
  test`, in a sandbox without network.
- `conformance-external` builds the simple fixture from a `src` without
  either lockfile, with `lockFile` and `pipfileLock` outside it, and runs
  `prefetch --lockfile` with the lockfile outside the project.
- `conformance-update` locks a copy of the simple fixture that allows any
  six while the local index serves six 1.16.0, adds six 1.17.0 to the
  index, and runs `update six`. Both lockfiles then pass the stale checks
  of the command and of the Nix library.

Each refusal check asks both `prefetch` and the Nix library, which
`nix-instantiate --eval --store dummy://` evaluates in the sandbox, and
greps each error for the command that fixes it. A damage that only the
Nix library finds, such as a missing URL with a correct `contentHash`, asks
the library alone, because `prefetch` leaves that check to the Nix build it
runs.

The other checks:

- `simple`, `simple-program`, `simple-categories`, `simple-package` and
  `simple-tests` build `tests/fixtures/simple`: a hatchling project,
  installed from its own directory, with attrs (a wheel), docopt (an sdist
  that the locked setuptools builds) and markupsafe (wheels for each CPU)
  in `default`, six in `develop`, iniconfig in the custom category `tools`,
  and a `[scripts] test` that `tests` runs.
- `sources` builds `tests/fixtures/sources`, with a package of every kind
  besides an index: attrs from git (hatch-vcs), six from a GitHub archive
  URL, a local directory, a local sdist and a local wheel.
  `sources-fetches` checks that `fetches` holds the git checkout and the
  archive. `prefetch-sources` runs `prefetch` on it and checks the editable
  install.
- `outside` builds `tests/fixtures/outside/app`, which depends on a path
  outside its directory through `pathSources`.
- `prefetch-stale-pipfile` adds a package to the Pipfile by hand and checks
  that `prefetch` refuses, naming `pipenv lock` and `pipenv-purifier lock`.
- `publish` uploads the simple fixture's release to a local index with
  `pipenv-purifier publish --release`.
- `real-world-pipenv` builds the `default` and `develop` categories of
  pypa/pipenv at `fef0293` from `tests/real-world/pipenv/` and runs its unit
  tests. It leaves out `tests/unit/test_release_tasks.py`, which imports
  bs4, a package that Pipenv's Pipfile does not list, and four tests that
  download from PyPI.
- `nix-library` tests wheel selection, name and path normalization, file
  names from URLs, the `systems` of wheels, and `checkLock` of the shared
  library on the committed lockfiles.
- `unit` runs `tests/test_pipenv_purifier.py`, the unit tests of the lock
  tool.
- `cli` runs the help of every command.

CI runs the checks on x86_64-linux and aarch64-linux.

`tests/relock-fixtures.sh` relocks every fixture against PyPI and GitHub
with the Pipenv and Python of the flake's package set. The lockfile of
Pipenv's repository is relocked by running `pipenv-purifier lock` in a copy
of the repository at the pinned commit and copying the lockfile to
`tests/real-world/pipenv/`.
