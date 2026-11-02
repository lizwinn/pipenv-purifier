# SPDX-License-Identifier: MIT
"""Checks that every package of an index that Pipfile.lock pins in some
categories is installed inside a virtual environment, at the locked
version. A package that pip took as already installed from outside the
environment, as from a PYTHONPATH of the build, is missing from it or has
another version. Runs with the environment's Python:

    <venv>/bin/python locked-in-venv.py <Pipfile.lock> <category>...
"""

import importlib.metadata
import json
import os
import re
import sys

pipfile_lock_path, *selected = sys.argv[1:]
with open(pipfile_lock_path) as f:
    pipfile_lock = json.load(f)
prefix = os.path.realpath(sys.prefix)
installed = {}
versions = {}
for distribution in importlib.metadata.distributions():
    location = os.path.realpath(str(distribution.locate_file("")))
    if location.startswith(prefix + os.sep):
        name = re.sub(r"[-_.]+", "-", distribution.metadata["Name"]).lower()
        installed[name] = distribution.version
        versions.setdefault(name, set()).add(distribution.version)
problems = []
for category in selected:
    for name, entry in pipfile_lock[category].items():
        if "version" not in entry or any(k in entry for k in ("git", "file", "path")):
            continue
        normal = re.sub(r"[-_.]+", "-", name).lower()
        version = entry["version"].removeprefix("==")
        if len(versions.get(normal, set())) > 1:
            problems.append(f"{name} has multiple installed versions in {prefix}: {sorted(versions[normal])}")
            continue
        found = installed.get(normal)
        if found is None:
            # A package whose markers leave it out on this system is not
            # installed, which pip decides by the same markers. pip, which
            # every virtual environment holds, vendors `packaging`.
            from pip._vendor.packaging.markers import Marker

            if "markers" in entry and not Marker(entry["markers"]).evaluate():
                continue
            problems.append(f"{name}=={version} is not installed in {prefix}")
        elif found != version:
            problems.append(f"{name} is installed in {prefix} at {found}, not at the locked {version}")
if problems:
    sys.exit("\n".join(problems))
print(f"every locked package of {', '.join(selected)} is in {prefix}")
