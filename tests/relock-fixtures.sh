#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Relocks the test fixtures: `pipenv lock`, then `pipenv-purifier lock`, in
# every fixture directory that holds a Pipfile, with the Pipenv and Python of
# the flake's package set, which are the ones the checks build with. It needs
# the network (PyPI and GitHub) and runs from the repository root:
#
#   tests/relock-fixtures.sh
#
# Name fixture directories as arguments to relock only those.
set -euo pipefail

cli=$(nix build --no-link --print-out-paths '.#cli')
pipenv=$(nix build --no-link --print-out-paths --inputs-from . 'nixpkgs#pipenv')
python=$(nix build --no-link --print-out-paths --inputs-from . 'nixpkgs#python3')

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export PIPENV_PYTHON="$python/bin/python3" PIPENV_VENV_IN_PROJECT=1 PIPENV_YES=1 PIPENV_NOSPIN=1
export PIPENV_CACHE_DIR="$scratch/pipenv-cache" PIP_CACHE_DIR="$scratch/pip-cache"
export XDG_CACHE_HOME="$scratch/cache" XDG_DATA_HOME="$scratch/data"

if [ "$#" -gt 0 ]; then
  fixtures=("$@")
else
  fixtures=()
  for pipfile in tests/fixtures/*/Pipfile tests/fixtures/*/*/Pipfile; do
    [ -e "$pipfile" ] && fixtures+=("$(dirname "$pipfile")")
  done
fi

for fixture in "${fixtures[@]}"; do
  echo "relocking $fixture" >&2
  (
    cd "$fixture"
    "$pipenv/bin/pipenv" lock
    rm -rf .venv
    "$cli/bin/pipenv-purifier" lock
  )
done
