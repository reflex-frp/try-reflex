{ pkgs, haskellLib, fetchFromGitHub }:
with haskellLib;
self: super: {
  cabal-macosx = dontCheck super.cabal-macosx;
  haddock-library-ghcjs = dontCheck super.haddock-library-ghcjs;
  haddock-api-ghcjs = dontCheck super.haddock-api-ghcjs;
}
