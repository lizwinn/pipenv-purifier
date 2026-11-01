import contextlib
import io
import unittest

import simple


class Simple(unittest.TestCase):
    def test_main_prints_the_locked_versions(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            simple.main()
        self.assertEqual(out.getvalue(), "simple attrs=25.3.0 docopt=0.6.2 markupsafe=3.0.3\n")

    def test_development_packages_are_installed(self):
        import six

        self.assertEqual(six.__version__, "1.17.0")


if __name__ == "__main__":
    unittest.main()
