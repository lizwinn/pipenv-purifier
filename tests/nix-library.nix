# SPDX-License-Identifier: MIT
#
# Unit tests of the Nix library that need no build: wheel selection, name
# normalization, and the check that pipenv-purifier.lock.json still matches
# Pipfile.lock.
{ pkgs }:
let
  inherit (pkgs) lib;

  installs = import ../nix/lib/wheels.nix {
    pythonVersion = "3.14";
    arch = "x86_64";
    glibcVersion = "2.40";
  };

  wheelCases = {
    pure = installs "attrs-25.3.0-py3-none-any.whl";
    pythonTwoAndThree = installs "six-1.17.0-py2.py3-none-any.whl";
    sameCpython = installs "pydantic_core-2.41.4-cp314-cp314-manylinux_2_17_x86_64.manylinux2014_x86_64.whl";
    otherCpython = installs "pydantic_core-2.41.4-cp313-cp313-manylinux_2_17_x86_64.manylinux2014_x86_64.whl";
    stableAbi = installs "cryptography-46.0.3-cp311-abi3-manylinux_2_34_x86_64.whl";
    stableAbiNewerThanPython = installs "cryptography-46.0.3-cp315-abi3-manylinux_2_34_x86_64.whl";
    newerGlibc = installs "numpy-2.3.4-cp314-cp314-manylinux_2_41_x86_64.whl";
    otherArch = installs "numpy-2.3.4-cp314-cp314-manylinux_2_28_aarch64.whl";
    musl = installs "numpy-2.3.4-cp314-cp314-musllinux_1_2_x86_64.whl";
    macos = installs "numpy-2.3.4-cp314-cp314-macosx_14_0_arm64.whl";
    windows = installs "pywin32-311-cp314-cp314-win_amd64.whl";
    buildTag = installs "example-1.0-1-py3-none-any.whl";
    pythonTwoOnly = installs "example-1.0-py2-none-any.whl";
  };

  wheelExpected = {
    pure = true;
    pythonTwoAndThree = true;
    sameCpython = true;
    otherCpython = false;
    stableAbi = true;
    stableAbiNewerThanPython = false;
    newerGlibc = false;
    otherArch = false;
    musl = false;
    macos = false;
    windows = false;
    buildTag = true;
    pythonTwoOnly = false;
  };

  current = import ../nix/lib/lock.nix { src = ./fixtures/simple; };

  normalizeCases = {
    "Foo.Bar_baz" = "foo-bar-baz";
    "zope.interface" = "zope-interface";
    "attrs" = "attrs";
    "Django--REST" = "django-rest";
  };

  pathCases = {
    "." = "";
    "./" = "";
    "./libs/greeting" = "libs/greeting";
    "libs/greeting/" = "libs/greeting";
  };

  # A Pipfile.lock that differs from the one pipenv-purifier.lock.json was
  # made for: the lockfile must be refused.
  changedPipfileLock = builtins.toFile "Pipfile.lock" (
    builtins.replaceStrings [ "\"==0.6.2\"" ] [ "\"==0.6.1\"" ] (
      builtins.readFile ./fixtures/simple/Pipfile.lock
    )
  );
  staleLock =
    builtins.tryEval
      (import ../nix/lib/lock.nix {
        src = ./fixtures/simple;
        pipfileLockFile = changedPipfileLock;
      }).purifier;
  currentLock = builtins.tryEval current.purifier.version;

  failures =
    lib.filter (name: wheelCases.${name} != wheelExpected.${name}) (lib.attrNames wheelCases)
    ++ lib.concatMap (
      name: lib.optional (current.normalize name != normalizeCases.${name}) "normalize ${name}"
    ) (lib.attrNames normalizeCases)
    ++ lib.concatMap (
      path: lib.optional (current.normalizePath path != pathCases.${path}) "normalizePath ${path}"
    ) (lib.attrNames pathCases)
    ++ lib.optional staleLock.success "a stale pipenv-purifier.lock.json was accepted"
    ++ lib.optional (!currentLock.success) "the current pipenv-purifier.lock.json was refused";
in
pkgs.runCommand "pipenv-purifier-test-nix-library" { } (
  if failures == [ ] then
    "touch $out"
  else
    ''
      echo "failed: "${lib.escapeShellArg (lib.concatStringsSep ", " failures)} >&2
      exit 1
    ''
)
