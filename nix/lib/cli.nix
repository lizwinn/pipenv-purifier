# SPDX-License-Identifier: MIT
#
# What the `pipenv-purifier` command builds for a project directory given as
# an absolute path, with the nixpkgs the command was built with:
# - `interactive`: the inputs of a development environment, which `sync`
#   installs into the project's .venv;
# - `package`: the sdist and wheel of the local package `package`, which
#   `publish` uploads.
#
# A local package that Pipfile.lock names by a path outside the project is
# read from that path.
{
  nixpkgs,
  src,
  attribute,
  package ? null,
}:
let
  pkgs = import nixpkgs { };
  inherit (pkgs) lib;

  # A directory without what Pipenv, Python and git leave in it.
  source =
    path:
    builtins.path {
      inherit path;
      name = "source";
      filter =
        p: type:
        !builtins.elem (baseNameOf p) [
          ".git"
          ".venv"
          "__pycache__"
          "dist"
        ];
    };

  root = /. + src;
  pipfileLock = builtins.fromJSON (builtins.readFile (root + "/Pipfile.lock"));
  localPaths = lib.concatMap (
    category:
    lib.concatMap (entry: lib.optional (entry ? path) entry.path) (
      lib.attrValues pipfileLock.${category}
    )
  ) (builtins.filter (k: k != "_meta") (lib.attrNames pipfileLock));
  outside = builtins.filter (
    path: path == ".." || lib.hasPrefix "../" path || lib.hasPrefix "/" path
  ) localPaths;
  # Nix paths are normalized, so ".." in the string leaves the project.
  absolute = path: if lib.hasPrefix "/" path then /. + path else /. + "${src}/${path}";
  pathSources = lib.genAttrs outside (
    path:
    let
      target = absolute path;
    in
    if lib.pathIsDirectory target then source target else target
  );

  project = pkgs.callPackage ./build-pipenv-project.nix { } {
    src = source root;
    inherit pathSources;
  };
in
if attribute == "interactive" then
  project.interactive
else if attribute == "package" then
  project.packages.${package}
    or (throw "pipenv-purifier: ${package} is no local package; the local packages are ${toString (builtins.attrNames project.packages)}")
else
  throw "pipenv-purifier: cli.nix builds `interactive` or `package`, not ${attribute}"
