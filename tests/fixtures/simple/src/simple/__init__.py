import importlib.metadata


def main():
    # markupsafe installs from a wheel for the build's CPU, and its compiled
    # speedups module loads only from such a wheel.
    from markupsafe import _speedups  # noqa: F401

    versions = " ".join(
        f"{name}={importlib.metadata.version(name)}"
        for name in ("attrs", "docopt", "markupsafe")
    )
    print(f"simple {versions}")
