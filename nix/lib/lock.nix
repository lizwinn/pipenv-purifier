# SPDX-License-Identifier: MIT
#
# Reads a Pipenv project's two lockfiles: Pipfile.lock, which Pipenv writes,
# and pipenv-purifier.lock.json, which `pipenv-purifier lock` writes beside
# it.
{
  # The project root, which holds the Pipfile and both lockfiles.
  src,
  lockFile ? src + "/pipenv-purifier.lock.json",
  pipfileLockFile ? src + "/Pipfile.lock",
}:
let
  inherit (builtins)
    attrNames
    concatLists
    concatStringsSep
    filter
    fromJSON
    genList
    hashFile
    hashString
    head
    listToAttrs
    map
    match
    readFile
    replaceStrings
    sort
    split
    substring
    stringLength
    ;

  supportedVersion = import ./lock-version.nix;

  purifier = builtins.addErrorContext "while reading ${toString lockFile}, which `pipenv-purifier lock` writes; run it again if the file is damaged" (
    fromJSON (readFile lockFile)
  );
  pipfileLock = builtins.addErrorContext "while reading ${toString pipfileLockFile}, which `pipenv lock` writes; run it again if the file is damaged" (
    fromJSON (readFile pipfileLockFile)
  );

  # The fields a lockfile of this format has.
  purifierFields = [
    "version"
    "inputsHash"
    "artifacts"
    "packages"
    "buildRequirements"
    "builds"
    "sources"
    "outputs"
  ];
  missingFields = filter (field: !(builtins.isAttrs purifier && purifier ? ${field})) purifierFields;

  concatMap = f: list: concatLists (map f list);
  unique =
    list:
    attrNames (
      listToAttrs (
        map (x: {
          name = x;
          value = null;
        }) list
      )
    );

  letters = text: genList (i: substring i 1 text) 26;
  lower = replaceStrings (letters "ABCDEFGHIJKLMNOPQRSTUVWXYZ") (
    letters "abcdefghijklmnopqrstuvwxyz"
  );

  # A project name as PEP 503 normalizes it (src/pipenv_purifier.py,
  # normalize): lower case, with every run of "-", "_" and "." one "-".
  normalize = name: lower (concatStringsSep "-" (filter builtins.isString (split "[-_.]+" name)));

  # The package categories of Pipfile.lock: `default`, `develop` and any
  # custom category of the Pipfile.
  categories = filter (k: k != "_meta") (attrNames pipfileLock);

  hasPrefix = prefix: text: substring 0 (stringLength prefix) text == prefix;
  insideProject = path: !(path == ".." || hasPrefix "/" path || hasPrefix "../" path);

  # A relative path without "." segments and trailing slashes, the way the
  # lock tool records paths with os.path.normpath; "" for the project root.
  normalizePath =
    path:
    concatStringsSep "/" (filter (s: builtins.isString s && s != "" && s != ".") (split "/" path));

  kindOf =
    entry:
    if entry ? git then
      "git"
    else if entry ? file then
      "file"
    else if entry ? path then
      "path"
    else
      "index";

  version = entry: replaceStrings [ "==" ] [ "" ] (entry.version or "");

  # The packages of one category, each with its normalized name, its key
  # ("<name>==<version>" for a package of an index, the name otherwise), its
  # kind and its entry of Pipfile.lock.
  packagesOf =
    category:
    map (
      name:
      let
        entry = pipfileLock.${category}.${name};
        kind = kindOf entry;
      in
      {
        name = normalize name;
        inherit kind entry;
        key = if kind == "index" then "${normalize name}==${version entry}" else normalize name;
      }
    ) (attrNames pipfileLock.${category});

  # Every locked file of an index or a URL by its path, as a file entry of
  # the shared purifier library.
  files = listToAttrs (
    map (artifact: {
      name = artifact.path;
      value = artifact;
    }) (filter (artifact: artifact ? url) purifier.artifacts)
  );

  # Every locked git checkout by its path, as a git entry of the shared
  # purifier library.
  gitEntries = listToAttrs (
    map (artifact: {
      name = artifact.path;
      value = artifact;
    }) (filter (artifact: artifact ? git) purifier.artifacts)
  );

  # The hash the lock tool records over Pipfile.lock and the pyproject.toml
  # files of the local source trees in the project (src/pipenv_purifier.py,
  # inputs_hash).
  localPaths = concatMap (
    c: map (p: p.entry.path) (filter (p: p.kind == "path") (packagesOf c))
  ) categories;
  treeFiles = sort (a: b: a < b) (
    unique (
      filter (f: builtins.pathExists (src + "/${f}")) (
        map (
          path:
          let
            normal = normalizePath path;
          in
          if normal == "" then "pyproject.toml" else "${normal}/pyproject.toml"
        ) (filter insideProject localPaths)
      )
    )
  );
  # Every package of an index that Pipfile.lock pins, with the problems of
  # its files in pipenv-purifier.lock.json: none recorded, or one whose hash
  # Pipfile.lock does not list for it. Pipfile.lock is the lockfile Pipenv
  # checked, so a file it does not list is one the lockfile was edited to
  # name, and the build refuses it before fetching anything.
  indexProblems = concatMap (
    category:
    concatMap (
      p:
      let
        listed = map (
          h:
          builtins.convertHash {
            hash = replaceStrings [ "sha256:" ] [ "" ] h;
            hashAlgo = "sha256";
            toHashFormat = "sri";
          }
        ) (p.entry.hashes or [ ]);
        locked = purifier.packages.${p.key} or null;
        names = if locked == null then [ ] else locked.wheels ++ filter (n: n != null) [ locked.sdist ];
      in
      if locked == null then
        [ "it has no files of ${p.key}, which Pipfile.lock pins" ]
      else
        concatMap (
          name:
          let
            file = files.${name} or null;
          in
          if file == null then
            [ "it names ${name} for ${p.key} but has no download entry of it" ]
          else if !builtins.elem file.hash listed then
            [ "it gives ${name} of ${p.key} the hash ${file.hash}, which Pipfile.lock does not list" ]
          else
            [ ]
        ) names
    ) (filter (p: p.kind == "index") (packagesOf category))
  ) categories;

  inputsHash = hashString "sha256" (
    "Pipfile.lock ${hashFile "sha256" pipfileLockFile}\n"
    + concatStringsSep "" (map (f: "${f} ${hashFile "sha256" (src + "/${f}")}\n") treeFiles)
  );

  # A store path name from a file name. Store path names allow
  # [A-Za-z0-9+._?=-], must not start with a dot, and are at most 211
  # characters; every other character becomes "_".
  storeName =
    name:
    let
      replaced = concatStringsSep "" (
        map (part: if builtins.isList part then "_" else part) (split "[^A-Za-z0-9+._?=-]" name)
      );
      undotted = head (match "\\.*(.*)" replaced);
    in
    substring 0 200 (if undotted == "" then "file" else undotted);
in
assert
  missingFields == [ ]
  || throw "pipenv-purifier: ${toString lockFile} is not a pipenv-purifier lockfile: it has no ${concatStringsSep ", " missingFields}. Run `pipenv-purifier lock`.";
assert
  purifier.version == supportedVersion
  || throw "pipenv-purifier: ${toString lockFile} has lock format version ${toString purifier.version}; this library reads version ${toString supportedVersion}. Run `pipenv-purifier lock` with the version that provides this library.";
assert
  purifier.inputsHash == inputsHash
  || throw "pipenv-purifier: ${toString lockFile} does not match Pipfile.lock and the pyproject.toml files of the local packages. Run `pipenv-purifier lock`.";
assert
  indexProblems == [ ]
  || throw "pipenv-purifier: ${toString lockFile} does not agree with Pipfile.lock: ${concatStringsSep "; " indexProblems}. Run `pipenv-purifier lock`.";
{
  inherit
    purifier
    pipfileLock
    categories
    packagesOf
    files
    gitEntries
    insideProject
    normalize
    normalizePath
    storeName
    ;
  inherit (purifier)
    packages
    builds
    buildRequirements
    sources
    outputs
    ;
  pythonVersion = pipfileLock._meta.requires.python_version or null;
}
