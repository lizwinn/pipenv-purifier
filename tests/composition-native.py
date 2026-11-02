#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Native Pipenv composition with relocated locks and ordinary downstream wheels."""
import json
import os
import sys
from pathlib import Path
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parent.parent
system = subprocess.check_output(['nix', 'eval', '--impure', '--raw', '--expr', 'builtins.currentSystem'], text=True).strip()
snapshot = json.loads(subprocess.check_output(['nix', 'flake', 'metadata', '--json',
    '--no-write-lock-file', 'path:' + str(root)], text=True))['path']
with tempfile.TemporaryDirectory(prefix='pipenv-native-composition-') as temporary:
    temporary = Path(temporary)
    subprocess.run(['nix-store', '--add-root', str(temporary / 'source'), '--realise', snapshot], check=True)
    cli = Path(subprocess.check_output(['nix', 'build', str(root) + '#cli', '--print-out-paths',
        '--out-link', str(temporary / 'cli')], text=True).strip()) / 'bin/pipenv-purifier'
    pipenv = cli.parent / 'pipenv'
    expression = '''let
      f = builtins.getFlake ("path:" + builtins.getEnv "PIPENV_COMPOSITION_FLAKE");
      p = f.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
      api = p.python3.withPackages (ps: [ ps.packaging ]);
    in p.runCommand "pipenv-composition-tools" {} ''
      mkdir -p "$out/bin"
      ln -s ${p.uv}/bin/uv "$out/bin/uv"
      ln -s ${p.python3.interpreter} "$out/bin/python"
      ln -s ${api}/bin/python "$out/bin/api-python"
    '' '''
    env = dict(os.environ, PIPENV_COMPOSITION_FLAKE=snapshot, UV_PYTHON_DOWNLOADS='never')
    tools = Path(subprocess.check_output(['nix', 'build', '--impure', '--print-out-paths',
        '--out-link', str(temporary / 'tools'), '--expr', expression], text=True, env=env).strip())
    project = temporary / 'project'
    source = project / 'src/pipenv_composed/__init__.py'
    source.parent.mkdir(parents=True)
    source.write_text('import simple\ndef main():\n    simple.main()\n')
    definition = project / 'pyproject.toml'
    definition.write_text('''[project]
name = "pipenv-composed"
version = "1.0"
requires-python = ">=3.12"
dependencies = ["simple>=99"]
[project.scripts]
pipenv-composed = "pipenv_composed:main"
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
''')
    pipfile = project / 'Pipfile'
    pipfile.write_text('''[[source]]
url = "https://pypi.org/simple"
verify_ssl = true
name = "pypi"
[packages]
simple = ">=99"
pipenv-composed = {path = ".", editable = true}
[requires]
python_version = "3.14"
[scripts]
test = "pipenv-composed"
''')
    original = definition.read_bytes(), pipfile.read_bytes()
    def run(*args, **kwargs):
        try:
            return subprocess.run([str(value) for value in args], cwd=project, env=env, check=True, **kwargs)
        except subprocess.CalledProcessError as error:
            if error.stderr:
                print(error.stderr, file=sys.stderr)
            raise
    unlocked = run(pipenv, '--version', capture_output=True, text=True)
    assert 'warning:' in unlocked.stderr and 'impurely' in unlocked.stderr
    reference = 'path:' + snapshot + '#checks.' + system + '.composition-producer'
    run(cli, 'lock', '--python', tools / 'bin/python', '--input', reference)
    lockfile, native = project / 'pipenv-purifier.lock.json', project / 'Pipfile.lock'
    lock = json.loads(lockfile.read_text())
    assert len(lock['projectInputs']) == 1 and not lock['sources']
    assert not any(Path(url).name.startswith(('simple-', 'attrs-', 'docopt-', 'markupsafe-'))
                   for url in lock['urls'].values()), 'provided bytes leaked into the download lock'
    before = lockfile.read_bytes(), native.read_bytes()
    run(cli, 'lock', '--python', tools / 'bin/python')
    assert before == (lockfile.read_bytes(), native.read_bytes())
    missing = '/nix/store/' + '0' * 32 + '-unavailable-python-projection'
    old = lock['projectInputs'][0]['nativeRepository']
    native.write_text(native.read_text().replace(old, missing))
    lock['projectInputs'][0]['nativeRepository'] = missing
    api = '''import importlib.util, json, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('native_lockfile', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
project = Path(sys.argv[2])
path = project / 'pipenv-purifier.lock.json'
lock = json.loads(sys.argv[3])
native = project / 'Pipfile.lock'
lock['inputsHash'] = module.inputs_hash(str(project), json.loads(native.read_text()), str(native))
lock['contentHash'] = module.content_hash(lock)
path.write_text(json.dumps(lock, indent=2) + chr(10))
'''
    run(tools / 'bin/api-python', '-c', api, root / 'src/pipenv_purifier.py', project, json.dumps(lock))
    bound = lockfile.read_bytes(), native.read_bytes()
    run(cli, 'prefetch')
    run(pipenv, 'sync')
    output = subprocess.check_output([str(pipenv), 'run', 'pipenv-composed'], cwd=project, env=env, text=True)
    assert output.strip() == 'simple attrs=25.3.0 docopt=0.6.2 markupsafe=3.0.3', output
    assert bound == (lockfile.read_bytes(), native.read_bytes())
    assert original == (definition.read_bytes(), pipfile.read_bytes())
    expression = '''let
      f = builtins.getFlake ("path:" + builtins.getEnv "PIPENV_COMPOSITION_FLAKE");
      p = import f.inputs.nixpkgs { overlays = [ f.overlays.default ]; };
      source = builtins.path {
        path = /. + builtins.getEnv "PIPENV_COMPOSITION_PROJECT";
        name = "source";
        filter = path: type: !(builtins.elem (baseNameOf path)
          [ ".git" ".venv" ".pipenv-purifier" "__pycache__" "dist" "build" "Pipfile.lock" ]);
      };
      project = p.pipenv-purifier.buildPipenvProject {
        src = source;
        pipfileLock = /. + builtins.getEnv "PIPENV_COMPOSITION_NATIVE_LOCK";
      };
    in [ project.tests project.packages.pipenv-composed.projections.python ]'''
    env.update(PIPENV_COMPOSITION_PROJECT=str(project), PIPENV_COMPOSITION_NATIVE_LOCK=str(native))
    built = json.loads(subprocess.check_output(['nix', 'build', '--impure', '--json',
        '--out-link', str(temporary / 'pure'), '--expr', expression], text=True, env=env))
    repository = Path(next(value['outputs']['out'] for value in built
                          if value['outputs']['out'].endswith('-python-projection')))
    downstream = temporary / 'downstream'
    run(tools / 'bin/uv', 'venv', '--python', tools / 'bin/python', downstream)
    run(tools / 'bin/uv', 'pip', 'install', '--python', downstream / 'bin/python',
        '--no-index', '--find-links', repository, 'pipenv-composed')
    assert subprocess.check_output([str(downstream / 'bin/pipenv-composed')], text=True).strip() == output.strip()
    run(downstream / 'bin/python', '-c',
        'from importlib.metadata import version; assert "+nix." in version("pipenv-composed"); assert "+nix." in version("simple")')
    uploads, portfile = temporary / 'uploads', temporary / 'port'
    server = subprocess.Popen([str(tools / 'bin/python'), str(root / 'tests/upload_server.py'),
                               '0', str(uploads), str(portfile)])
    try:
        deadline = time.monotonic() + 30
        while not portfile.exists():
            assert server.poll() is None and time.monotonic() < deadline
            time.sleep(0.05)
        result = run(cli, 'publish', '--', '--publish-url', 'http://127.0.0.1:' + portfile.read_text() + '/',
                     '--username', 'test', '--password', 'test', stderr=subprocess.PIPE, text=True)
        publication = Path(next(line.removeprefix('pipenv-purifier: publishing files Nix built in ')
            for line in result.stderr.splitlines() if line.startswith('pipenv-purifier: publishing files Nix built in ')))
        assert {path.name for path in uploads.glob('*.whl')} == {path.name for path in publication.glob('*.whl')}
        for path in publication.glob('*.whl'):
            assert path.read_bytes() == (uploads / path.name).read_bytes()
    finally:
        server.terminate()
        server.wait(timeout=10)
    assert original == (definition.read_bytes(), pipfile.read_bytes())
    print('PIPENV NATIVE, RELOCATABLE, PURE AND ORDINARY DOWNSTREAM COMPOSITION PASSED', flush=True)
