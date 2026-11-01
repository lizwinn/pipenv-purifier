# SPDX-License-Identifier: MIT
#
# The fetcher for locked files.
#
# A file with one URL is a fixed-output derivation on Nix's built-in fetcher
# (the same derivation <nix/fetchurl.nix> makes). A file with mirrors needs a
# fetcher that tries several URLs, so it is nixpkgs' `fetchurl` with `urls`.
# A fixed-output store path depends only on its name and hash, so both
# produce the same path for the same file.
#
# `fetchurl`, when given, replaces both. It is called with
# { name, urls, hash } and is the place for credentials (nixpkgs' fetchurl
# takes `netrcPhase`) or more mirrors.
{
  # nixpkgs' fetchurl, for files with mirrors.
  nixpkgsFetchurl,
  fetchurl ? null,
}:
# `hash` is the SRI hash of the file. `mirrors` are URLs that serve the same
# file, tried after `url`.
{
  name,
  url,
  mirrors,
  hash,
}:
let
  urls = [ url ] ++ mirrors;
in
if fetchurl != null then
  fetchurl { inherit name urls hash; }
else if mirrors != [ ] then
  nixpkgsFetchurl { inherit name urls hash; }
else
  derivation {
    inherit name url;
    builder = "builtin:fetchurl";
    system = "builtin";
    urls = [ url ];
    outputHash = hash;
    outputHashAlgo = "sha256";
    outputHashMode = "flat";
    unpack = false;
    executable = false;
    preferLocalBuild = true;
    impureEnvVars = [
      "http_proxy"
      "https_proxy"
      "ftp_proxy"
      "all_proxy"
      "no_proxy"
    ];
  }
