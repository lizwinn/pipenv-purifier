# SPDX-License-Identifier: MIT
#
# The flake's checks. Every one builds in the sandbox; the only network
# access is the fixed-output fetches of locked files.
{
  pkgs,
  # The flake's default package overlay, which adds buildPipenvProject.
  overlay,
  cli,
}:
let
  inherit (pkgs) lib;

  # Every fixture builds the way a consumer's package does: through
  # buildPipenvProject of a package set the overlay applies to.
  withOverlay = pkgs.extend overlay;
  inherit (withOverlay) buildPipenvProject runCommand;

  # A hatchling project, installed from its own directory, that depends on
  # attrs, which installs from its wheel, and on docopt, which has only an
  # sdist and is built with the locked setuptools. six is a development
  # package.
  simple = buildPipenvProject { src = ./fixtures/simple; };
  simpleDevelop = buildPipenvProject {
    src = ./fixtures/simple;
    categories = [
      "default"
      "develop"
    ];
  };
  # The custom category `tools` alone.
  simpleTools = buildPipenvProject {
    src = ./fixtures/simple;
    categories = [ "tools" ];
  };

  # A project with a package of every kind Pipfile.lock records besides an
  # index: attrs from git (built with hatch-vcs, which reads its version
  # from git), six from a GitHub archive URL, and packages from a local
  # directory, a local sdist and a local wheel.
  sources = buildPipenvProject { src = ./fixtures/sources; };

  # A project that depends on an editable path outside its directory,
  # which the build gets through pathSources.
  outside = buildPipenvProject {
    src = ./fixtures/outside/app;
    pathSources."../shared" = ./fixtures/outside/shared;
  };

  # pypiserver imports cgi, which Python 3.13 removed; legacy-cgi provides
  # it.
  pypiserver = pkgs.python3.withPackages (ps: [
    ps.pypiserver
    ps.legacy-cgi
  ]);

  # Every locked file of the simple fixture, in one directory, which a
  # local package index serves.
  simpleFiles = pkgs.linkFarm "pipenv-purifier-test-simple-files" (
    lib.mapAttrsToList (path: file: {
      name = path;
      path = pkgs.fetchurl {
        name = simple.lock.storeName path;
        inherit (file) url hash;
      };
    }) simple.lock.files
  );

  # Starts a package index on 127.0.0.1:8080 that serves a directory and
  # takes uploads into it without authentication, and waits until it
  # answers.
  startIndex = directory: ''
    ${pypiserver.interpreter} -m pypiserver run --port 8080 --host 127.0.0.1 \
      --authenticate . --passwords . --disable-fallback ${directory} &
    for _ in $(seq 100); do
      ${pkgs.python3.interpreter} -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8080/simple/")' 2>/dev/null && break
      sleep 0.1
    done
  '';

  # Runs a program and compares what it prints.
  runs =
    name: program: expected:
    runCommand "pipenv-purifier-test-${name}" { } ''
      output=$(${program})
      echo "$output"
      if [ "$output" != ${lib.escapeShellArg expected} ]; then
        echo "expected: "${lib.escapeShellArg expected} >&2
        exit 1
      fi
      touch $out
    '';

  # Runs `pipenv-purifier sync` on a copy of a fixture, with the inputs Nix
  # built for it, then runs a script of the .venv it installed. `edit`
  # changes the project's source afterwards, and the script runs again: a
  # local package installed as editable prints `edited`.
  syncs =
    name: fixture: project: script: expected: edit: edited:
    runCommand "pipenv-purifier-test-sync-${name}" { nativeBuildInputs = [ cli ]; } ''
      cp -r ${fixture} project
      chmod -R u+w project
      cd project
      # Python checks its cached bytecode by the modification time in
      # seconds and the size of the source, so the edit right after the
      # first run would go unseen through a cache.
      export HOME=$TMPDIR PYTHONDONTWRITEBYTECODE=1
      pipenv-purifier sync --inputs ${project.interactive}
      check() {
        output=$(.venv/bin/${script})
        echo "$output"
        if [ "$output" != "$1" ]; then
          echo "expected: $1" >&2
          exit 1
        fi
      }
      check ${lib.escapeShellArg expected}
      ${edit}
      check ${lib.escapeShellArg edited}
      touch $out
    '';
in
{
  simple =
    runs "simple" "${simple.environment}/bin/simple"
      "simple attrs=25.3.0 docopt=0.6.2 markupsafe=3.0.3";

  # The program of the script `simple`, which `nix run` runs.
  simple-program =
    runs "simple-program" (lib.getExe simple.programs.simple)
      "simple attrs=25.3.0 docopt=0.6.2 markupsafe=3.0.3";

  # `default` alone leaves out the development package six and the package
  # of the custom category `tools`, and each category adds its packages.
  simple-categories = runCommand "pipenv-purifier-test-categories" { } ''
    ${simple.environment}/bin/python -c 'import six' 2>/dev/null && { echo "six is in the default environment" >&2; exit 1; }
    ${simple.environment}/bin/python -c 'import iniconfig' 2>/dev/null && { echo "iniconfig is in the default environment" >&2; exit 1; }
    ${simpleDevelop.environment}/bin/python -c 'import six; print(six.__version__)'
    ${simpleTools.environment}/bin/python -c 'import iniconfig; print(iniconfig.__name__)'
    touch $out
  '';

  # A local package's sdist and wheel, named without building by the
  # lockfile.
  simple-package = runCommand "pipenv-purifier-test-simple-package" { } ''
    test -f ${simple.packages.simple.artifacts."simple-0.1.0.tar.gz"}
    test -f ${simple.packages.simple.artifacts."simple-0.1.0-py3-none-any.whl"}
    test -f ${simple.packages.simple.artifacts.sdist}
    test -f ${simple.packages.simple.artifacts.wheel}
    touch $out
  '';

  sources =
    runs "sources" "${sources.environment}/bin/sources"
      "attrs=25.3.0 six=1.17.0 localdir 0.3.0 localsdist 0.4.0 localwheel 0.5.0";

  outside = runs "outside" "${outside.environment}/bin/outside-app" "outside-app with shared 0.2.0";

  sync-sources =
    syncs "sources" ./fixtures/sources sources "sources"
      "attrs=25.3.0 six=1.17.0 localdir 0.3.0 localsdist 0.4.0 localwheel 0.5.0"
      "sed -i 's/attrs=/attrs: /' src/sources/__init__.py"
      "attrs: 25.3.0 six=1.17.0 localdir 0.3.0 localsdist 0.4.0 localwheel 0.5.0";

  sync-simple =
    syncs "simple" ./fixtures/simple simple "simple" "simple attrs=25.3.0 docopt=0.6.2 markupsafe=3.0.3"
      "sed -i 's/simple {versions}/edited {versions}/' src/simple/__init__.py"
      "edited attrs=25.3.0 docopt=0.6.2 markupsafe=3.0.3";

  # The lock run, against a local index that serves the files of the simple
  # fixture's lock: `pipenv lock`, then `pipenv-purifier lock`, which has to
  # find every file, resolve the same build requirements and record the same
  # outputs as the committed lockfile. The index serves PEP 503 pages, so
  # this also covers the lock tool's reading of HTML index pages.
  lock-run =
    runCommand "pipenv-purifier-test-lock-run"
      {
        nativeBuildInputs = [
          cli
          withOverlay.pipenv
        ];
      }
      ''
        export HOME=$TMPDIR PIPENV_VENV_IN_PROJECT=1 PIPENV_YES=1 PIPENV_NOSPIN=1
        export PIPENV_PYTHON=${pkgs.python3.interpreter}
        export PIPENV_CACHE_DIR=$TMPDIR/pipenv-cache PIP_CACHE_DIR=$TMPDIR/pip-cache
        mkdir packages
        cp ${simpleFiles}/* packages/
        ${startIndex "packages"}
        cp -r ${./fixtures/simple} project
        chmod -R u+w project
        cd project
        sed -i 's|https://pypi.org/simple|http://127.0.0.1:8080/simple|' Pipfile
        pipenv lock
        rm -rf .venv
        pipenv-purifier lock
        ${pkgs.python3.interpreter} - ${./fixtures/simple/pipenv-purifier.lock.json} pipenv-purifier.lock.json <<'EOF'
        import json, sys
        committed, made = (json.load(open(p)) for p in sys.argv[1:])
        def shape(lock):
            artifacts = {a["path"]: a["hash"] for a in lock["artifacts"]}
            return {
                "artifacts": artifacts,
                "packages": lock["packages"],
                "buildRequirements": lock["buildRequirements"],
                "builds": lock["builds"],
                "outputs": lock["outputs"],
            }
        if shape(committed) != shape(made):
            for key in shape(committed):
                if shape(committed)[key] != shape(made)[key]:
                    print(f"{key} differs:\n{shape(committed)[key]}\n{shape(made)[key]}", file=sys.stderr)
            sys.exit(1)
        EOF
        touch $out
      '';

  # `publish --dist` uploads the sdist and wheel Nix built to an index.
  publish = runCommand "pipenv-purifier-test-publish" { nativeBuildInputs = [ cli ]; } ''
    export HOME=$TMPDIR UV_CACHE_DIR=$TMPDIR/uv-cache
    mkdir packages
    ${startIndex "packages"}
    pipenv-purifier publish --dist ${simple.packages.simple} -- \
      --publish-url http://127.0.0.1:8080/ --username user --password password
    test -f packages/simple-0.1.0.tar.gz
    test -f packages/simple-0.1.0-py3-none-any.whl
    touch $out
  '';

  nix-library = import ./nix-library.nix { inherit pkgs; };

  cli = runCommand "pipenv-purifier-test-cli" { } ''
    ${lib.getExe cli} --help
    ${lib.getExe cli} lock --help
    ${lib.getExe cli} sync --help
    ${lib.getExe cli} publish --help
    touch $out
  '';
}
