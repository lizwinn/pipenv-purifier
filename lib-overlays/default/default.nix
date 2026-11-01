# SPDX-License-Identifier: MIT
#
# The `pipenv-purifier` library namespace. It holds nothing: the builder
# needs a package set, so it is the package `buildPipenvProject` that the
# default package overlay adds.
{ ... }:
{

  overlay = final: prev: {
    pipenv-purifier = prev.pipenv-purifier or { };
  };

}
