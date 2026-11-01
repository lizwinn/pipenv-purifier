# SPDX-License-Identifier: MIT
#
# The `pipenv-purifier` command. It runs with the Pipenv of this package set,
# which is also the Pipenv that buildPipenvProject runs, so the build
# requirements that `pipenv-purifier lock` resolves are resolved by the Pipenv
# that installs from them. `sync` and `publish` build with the Nix library
# and the nixpkgs of this package set, and `publish` uploads with uv.
{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  pipenv,
  uv,
  git,
  nix-prefetch-git,
  path,
  # The source of the shared purifier library.
  purifierSource,
}:
let
  # The lock run reads requirements with `packaging` and builds the local
  # packages with `build` to record their outputs.
  python = python3.withPackages (ps: [
    ps.packaging
    ps.build
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "pipenv-purifier";
  version = lib.removeSuffix "\n" (builtins.readFile ../../version.txt);

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../src
      ../../nix/lib
    ];
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/pipenv-purifier
    cp src/pipenv_purifier.py $out/share/pipenv-purifier/
    cp -r nix/lib $out/share/pipenv-purifier/nix-lib
    makeWrapper ${python.interpreter} $out/bin/pipenv-purifier \
      --add-flags "-I $out/share/pipenv-purifier/pipenv_purifier.py" \
      --prefix PATH : ${
        lib.makeBinPath [
          pipenv
          uv
          git
          nix-prefetch-git
        ]
      } \
      --set-default PIPENV_PURIFIER_PYTHON ${python3.interpreter} \
      --set PIPENV_PURIFIER_NIX_LIB $out/share/pipenv-purifier/nix-lib \
      --set PIPENV_PURIFIER_NIXPKGS ${path} \
      --set PIPENV_PURIFIER_LIBRARY ${purifierSource}
    runHook postInstall
  '';

  meta = {
    description = "Lock, install and publish Pipenv projects that Nix builds";
    license = lib.licenses.mit;
    mainProgram = "pipenv-purifier";
  };
}
