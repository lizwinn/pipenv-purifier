# SPDX-License-Identifier: MIT
"""Unit tests of the lock tool's parsing and naming: project names, file
names and URLs, index pages, the throwaway Pipfile of a set of build
requirements, the rewritten Pipfile.lock of `sync`, the scripts of a wheel,
and the inputs hash. The flake check `unit` runs them."""

import json
import os
import tempfile
import unittest
import zipfile

from packaging.requirements import Requirement

import pipenv_purifier as p


class Names(unittest.TestCase):
    def test_normalize(self):
        self.assertEqual(p.normalize("Foo.Bar_baz"), "foo-bar-baz")
        self.assertEqual(p.normalize("zope.interface"), "zope-interface")
        self.assertEqual(p.normalize("Django--REST"), "django-rest")

    def test_package_key(self):
        self.assertEqual(p.package_key("MarkupSafe", {"version": "==3.0.3"}), "markupsafe==3.0.3")

    def test_file_name_decodes_percent_escapes(self):
        self.assertEqual(
            p.file_name("https://files.example/packages/ab/cd/torch-2.0.0%2Bcpu-cp314-cp314-linux_x86_64.whl"),
            "torch-2.0.0+cpu-cp314-cp314-linux_x86_64.whl",
        )

    def test_file_name_ignores_query_and_fragment(self):
        self.assertEqual(p.file_name("https://x.example/a/six-1.17.0.tar.gz?x=1#sha256=ab"), "six-1.17.0.tar.gz")

    def test_without_credentials(self):
        self.assertEqual(
            p.without_credentials("https://user:secret@index.example/simple/x/"),
            "https://index.example/simple/x/",
        )
        self.assertEqual(p.without_credentials("https://index.example/simple/"), "https://index.example/simple/")

    def test_pure_wheel(self):
        self.assertTrue(p.is_pure_wheel("attrs-25.3.0-py3-none-any.whl"))
        self.assertFalse(p.is_pure_wheel("markupsafe-3.0.3-cp314-cp314-manylinux_2_17_x86_64.whl"))
        self.assertFalse(p.is_pure_wheel("cryptography-46.0.3-cp311-abi3-manylinux_2_34_x86_64.whl"))

    def test_direct_kind(self):
        self.assertEqual(p.direct_kind({"git": "https://x", "ref": "a" * 40}), "git")
        self.assertEqual(p.direct_kind({"file": "https://x/a.tar.gz"}), "file")
        self.assertEqual(p.direct_kind({"path": ".", "editable": True}), "path")
        self.assertEqual(p.direct_kind({"version": "==1", "hashes": []}), "index")

    def test_categories(self):
        lock = {"_meta": {}, "default": {}, "develop": {}, "tools": {}}
        self.assertEqual(p.categories(lock), ["default", "develop", "tools"])

    def test_inside_project(self):
        self.assertTrue(p.inside_project("."))
        self.assertTrue(p.inside_project("vendor/x"))
        self.assertFalse(p.inside_project(".."))
        self.assertFalse(p.inside_project("../shared"))
        self.assertFalse(p.inside_project("/abs/path"))

    def test_sri(self):
        self.assertEqual(
            p.sri("427318ce031701fea540783410126f03899a97ffc6f61596ad581ac2e40e3bc3"),
            "sha256-QnMYzgMXAf6lQHg0EBJvA4mal//G9hWWrVgawuQOO8M=",
        )


class IndexPages(unittest.TestCase):
    PAGE = "https://index.example/simple/attrs/"

    def test_json_page(self):
        body = json.dumps(
            {
                "files": [
                    {
                        "filename": "attrs-25.3.0-py3-none-any.whl",
                        "url": "../../packages/attrs-25.3.0-py3-none-any.whl",
                        "hashes": {"sha256": "aa"},
                    },
                    {"filename": "attrs-25.3.0.tar.gz", "url": "https://files.example/attrs-25.3.0.tar.gz", "hashes": {}},
                ]
            }
        ).encode()
        self.assertEqual(
            p.parse_index_page(body, "application/vnd.pypi.simple.v1+json", self.PAGE),
            {"aa": ("attrs-25.3.0-py3-none-any.whl", "https://index.example/packages/attrs-25.3.0-py3-none-any.whl")},
        )

    def test_html_page(self):
        body = b"""<html><body>
        <a href="../../packages/attrs-25.3.0-py3-none-any.whl#sha256=aa">attrs-25.3.0-py3-none-any.whl</a>
        <a href="https://u:p@files.example/attrs-25.3.0.tar.gz#sha256=bb" data-requires-python="&gt;=3.8">sdist</a>
        <a href="https://files.example/attrs-24.0.0.tar.gz">no hash</a>
        </body></html>"""
        self.assertEqual(
            p.parse_index_page(body, "text/html", self.PAGE),
            {
                "aa": ("attrs-25.3.0-py3-none-any.whl", "https://index.example/packages/attrs-25.3.0-py3-none-any.whl"),
                "bb": ("attrs-25.3.0.tar.gz", "https://files.example/attrs-25.3.0.tar.gz"),
            },
        )


class BuildRequirements(unittest.TestCase):
    def test_pipfile_entry_joins_specifiers(self):
        entry = p.pipfile_entry([Requirement("setuptools>=40.8.0"), Requirement("setuptools<90")])
        self.assertEqual(sorted(entry["version"].split(",")), ["<90", ">=40.8.0"])

    def test_pipfile_entry_extras_and_markers(self):
        self.assertEqual(
            p.pipfile_entry([Requirement("hatchling[x]; python_version >= '3.9'")]),
            {"version": "*", "extras": ["x"], "markers": 'python_version >= "3.9"'},
        )

    def test_toml_value(self):
        self.assertEqual(p.toml_value({"version": "*", "extras": ["a"]}), '{ "version" = "*", "extras" = ["a"] }')

    def test_default_build_requires(self):
        self.assertEqual(p.build_requires({}), ["setuptools>=40.8.0"])
        self.assertEqual(p.build_requires({"build-system": {"requires": ["hatchling"]}}), ["hatchling"])


class Rewrite(unittest.TestCase):
    def test_rewrite_for_sync(self):
        with tempfile.TemporaryDirectory() as built:
            open(os.path.join(built, "attrs-25.3.0-py3-none-any.whl"), "w").close()
            lock = {
                "_meta": {},
                "default": {
                    "attrs": {"git": "https://github.com/python-attrs/attrs", "ref": "a" * 40, "markers": "m"},
                    "six": {"file": "https://x/six.tar.gz"},
                    "app": {"path": ".", "editable": True},
                    "lib": {"path": "../lib"},
                    "idna": {"version": "==3.0", "hashes": ["sha256:aa"]},
                },
            }
            out = p.rewrite(
                lock,
                {"attrs": built, "six": "/nix/store/six.tar.gz"},
                lambda path: os.path.normpath(os.path.join("/project", path)),
                keep_editable=True,
            )
        self.assertEqual(
            out["default"]["attrs"],
            {"markers": "m", "path": os.path.join(built, "attrs-25.3.0-py3-none-any.whl"), "editable": False},
        )
        self.assertEqual(out["default"]["six"], {"path": "/nix/store/six.tar.gz", "editable": False})
        self.assertEqual(out["default"]["app"], {"path": "/project", "editable": True})
        self.assertEqual(out["default"]["lib"], {"path": "/lib"})
        self.assertEqual(out["default"]["idna"], lock["default"]["idna"])
        self.assertIn("git", lock["default"]["attrs"], "the rewrite changed the original")

    def test_rewrite_needs_every_locked_source(self):
        lock = {"_meta": {}, "default": {"six": {"file": "https://x/six.tar.gz"}}}
        with self.assertRaises(p.Error):
            p.rewrite(lock, {}, lambda path: path, keep_editable=True)


class Outputs(unittest.TestCase):
    def test_wheel_scripts(self):
        with tempfile.TemporaryDirectory() as d:
            wheel = os.path.join(d, "app-1.0-py3-none-any.whl")
            with zipfile.ZipFile(wheel, "w") as z:
                z.writestr(
                    "app-1.0.dist-info/entry_points.txt",
                    "[console_scripts]\napp = app:main\nb-tool=app:b\n\n[gui_scripts]\napp-gui = app:gui\n\n[other]\nx = y\n",
                )
            self.assertEqual(p.wheel_scripts(wheel), ["app", "app-gui", "b-tool"])

    def test_wheel_without_scripts(self):
        with tempfile.TemporaryDirectory() as d:
            wheel = os.path.join(d, "lib-1.0-py3-none-any.whl")
            with zipfile.ZipFile(wheel, "w") as z:
                z.writestr("lib-1.0.dist-info/METADATA", "Name: lib\n")
            self.assertEqual(p.wheel_scripts(wheel), [])


class DamagedPipfileLock(unittest.TestCase):
    def read(self, text):
        with tempfile.TemporaryDirectory() as root:
            if text is not None:
                with open(os.path.join(root, "Pipfile.lock"), "w") as f:
                    f.write(text)
            return p.read_pipfile_lock(root)

    def test_missing(self):
        with self.assertRaisesRegex(p.Error, "run `pipenv lock` first"):
            self.read(None)

    def test_not_json(self):
        with self.assertRaisesRegex(p.Error, "is not valid JSON.*run `pipenv lock`"):
            self.read('{"_meta": {')

    def test_not_a_pipfile_lock(self):
        with self.assertRaisesRegex(p.Error, "is not a Pipfile.lock"):
            self.read('["a list"]')

    def test_valid(self):
        self.assertEqual(self.read('{"_meta": {}, "default": {}}'), {"_meta": {}, "default": {}})


class InputsHash(unittest.TestCase):
    def test_hash_covers_local_pyprojects_inside_the_project(self):
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, "libs", "a"))
            for path, text in (
                ("Pipfile.lock", "{}"),
                ("pyproject.toml", "[project]\n"),
                ("libs/a/pyproject.toml", "[project]\n"),
            ):
                with open(os.path.join(root, path), "w") as f:
                    f.write(text)
            lock = {
                "_meta": {},
                "default": {"app": {"path": "."}, "a": {"path": "./libs/a"}, "out": {"path": "../outside"}},
            }
            self.assertEqual(p.tree_files(root, lock), ["libs/a/pyproject.toml", "pyproject.toml"])
            before = p.inputs_hash(root, lock)
            with open(os.path.join(root, "libs/a/pyproject.toml"), "a") as f:
                f.write("# changed\n")
            self.assertNotEqual(before, p.inputs_hash(root, lock))


if __name__ == "__main__":
    unittest.main()
