{ lib
, haskellLib
, nixpkgs
, useFastWeak, useReflexOptimizer, enableLibraryProfiling, enableTraceReflexEvents
, useTextJSString, enableExposeAllUnfoldings, __useTemplateHaskell
, ghcSavedSplices
, haskellOverlaysPre
, haskellOverlaysPost
}:

let
  inherit (nixpkgs.buildPackages) thunkSet runCommand fetchgit fetchFromGitHub fetchFromBitbucket;
  inherit (nixpkgs) hackGet;
in

rec {
  optionalExtension = cond: overlay: if cond then overlay else _: _: {};

  versionWildcard = versionList: let
    versionListInc = lib.init versionList ++ [ (lib.last versionList + 1) ];
    bottom = lib.concatStringsSep "." (map toString versionList);
    top = lib.concatStringsSep "." (map toString versionListInc);
  in version: lib.versionOlder version top && lib.versionAtLeast version bottom;

  foldExtensions = lib.foldr lib.composeExtensions (_: _: {});

  getGhcVersion = ghc:
    if ghc.isGhcjs or false
    then ghc.ghcVersion
    else ghc.version;

  ##
  ## Conventional roll ups of all the constituent overlays below.
  ##

  # `super.ghc` is used so that the use of an overlay does not depend on that
  # overlay. At the cost of violating the usual rules on using `self` vs
  # `super`, this avoids a bunch of strictness issues keeping us terminating.
  combined = self: super: foldExtensions [
    user-custom-pre

    reflexPackages
    profiling
    untriaged

    (optionalExtension enableExposeAllUnfoldings exposeAllUnfoldings)

    combined-any
    (optionalExtension (!(super.ghc.isGhcjs or false)) combined-ghc)
    (optionalExtension (super.ghc.isGhcjs or false) combined-ghcjs)

    (optionalExtension (super.ghc.isGhcjs or false && useTextJSString) textJSString)
    (optionalExtension (with nixpkgs.stdenv; versionWildcard [ 8 6 ] super.ghc.version && !(super.ghc.isGhcjs or false) && hostPlatform != buildPlatform) loadSplices)

    (optionalExtension (nixpkgs.stdenv.hostPlatform.useAndroidPrebuilt or false) android)
    (optionalExtension (nixpkgs.stdenv.hostPlatform.isiOS or false) ios)
    (optionalExtension (nixpkgs.stdenv.hostPlatform.isWasm or false) wasm)

    user-custom-post
  ] self super;

  combined-any = self: super: foldExtensions [
    any
    (optionalExtension (versionWildcard [ 8 ] (getGhcVersion super.ghc)) combined-any-8)
  ] self super;

  combined-any-8 = self: super: foldExtensions [
    any-8
    (optionalExtension (versionWildcard [ 8 6 ] (getGhcVersion super.ghc)) any-8_6)
    (optionalExtension (lib.versionOlder "8.7"  (getGhcVersion super.ghc)) any-head)
  ] self super;

  combined-ghc = self: super: foldExtensions [
    (optionalExtension (versionWildcard [ 8 6 ] super.ghc.version) ghc-8_6)
    (optionalExtension (lib.versionOlder "8.7"  super.ghc.version) ghc-head)
  ] self super;

  combined-ghcjs = self: super: foldExtensions [
    ghcjs
    (optionalExtension (versionWildcard [ 8 6 ] super.ghc.ghcVersion) ghcjs-8_6)
    (optionalExtension useFastWeak ghcjs-fast-weak)
  ] self super;

  ##
  ## Constituent
  ##

  reflexPackages = import ./reflex-packages {
    inherit
      haskellLib lib nixpkgs thunkSet fetchFromGitHub fetchFromBitbucket hackGet
      useFastWeak useReflexOptimizer enableTraceReflexEvents enableLibraryProfiling __useTemplateHaskell
      ;
  };
  exposeAllUnfoldings = import ./expose-all-unfoldings.nix { };
  textJSString = import ./text-jsstring {
    inherit lib haskellLib fetchFromGitHub versionWildcard;
    inherit (nixpkgs) fetchpatch thunkSet;
  };

  # For GHC and GHCJS
  any = _: _: {};
  any-8 = import ./any-8.nix { inherit haskellLib lib getGhcVersion; };
  any-8_6 = import ./any-8.6.nix { inherit haskellLib fetchFromGitHub; inherit (nixpkgs) pkgs; };
  any-head = import ./any-head.nix { inherit haskellLib fetchFromGitHub; };

  # Just for GHC, usually to sync with GHCJS
  ghc-8_6 = _: _: {};
  ghc-head = _: _: {};

  profiling = import ./profiling.nix {
    inherit haskellLib;
    inherit enableLibraryProfiling;
  };

  saveSplices = import ./splices-load-save/save-splices.nix {
    inherit lib haskellLib fetchFromGitHub;
  };

  loadSplices = import ./splices-load-save/load-splices.nix {
    inherit lib haskellLib fetchFromGitHub;
    splicedHaskellPackages = ghcSavedSplices;
  };

  # Just for GHCJS
  ghcjs = import ./ghcjs.nix {
    inherit
      lib haskellLib nixpkgs fetchgit fetchFromGitHub
      useReflexOptimizer
      enableLibraryProfiling
      ;
  };
  ghcjs-fast-weak = import ./ghcjs-fast-weak {
   inherit lib;
  };
  ghcjs-8_6 = optionalExtension useTextJSString
    (import ./ghcjs-8.6-text-jsstring.nix { inherit lib fetchgit; });

  android = import ./android {
    inherit haskellLib;
    inherit nixpkgs;
    inherit thunkSet;
  };
  ios = import ./ios.nix {
    inherit haskellLib;
    inherit (nixpkgs) lib;
  };

  untriaged = import ./untriaged.nix {
    inherit haskellLib;
    inherit fetchFromGitHub;
    inherit nixpkgs;
  };

  haskell-language-server = import ./haskell-language-server {
    inherit haskellLib;
    inherit fetchFromGitHub;
    inherit nixpkgs;
    inherit thunkSet;
  };

  wasm = import ./wasm;

  user-custom-pre = foldExtensions haskellOverlaysPre;
  user-custom-post = foldExtensions haskellOverlaysPost;
}
