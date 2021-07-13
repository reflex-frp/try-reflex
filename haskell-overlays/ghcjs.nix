{ lib, haskellLib, nixpkgs, fetchgit, fetchFromGitHub
, useReflexOptimizer
, enableLibraryProfiling
}:

with haskellLib;

self: super: {
  _dep = super._dep or {} // {
    ghcjsBaseSrc = fetchgit {
      url = "https://github.com/ghcjs/ghcjs-base.git";
      rev = "6be0e992e292db84ab42691cfb172ab7cd0e709e";
      sha256 = "0nk7a01lprf40zsiph3ikwcqcdb1lghlj17c8zzhiwfmfgcc678g";
    };
  };

  # Profiling failures seee https://github.com/ghcjs/ghcjs/issues/759
  optparse-applicative = haskellLib.overrideCabal super.optparse-applicative (drv: {
    broken = drv.broken or false || enableLibraryProfiling;
  });
  th-orphans = haskellLib.overrideCabal super.th-orphans (drv: {
    broken = drv.broken or false || enableLibraryProfiling;
  });

  ghcWithPackages = selectFrom: nixpkgs.buildPackages.callPackage (nixpkgs.path + "/pkgs/development/haskell-modules/with-packages-wrapper.nix") {
    inherit (self) ghc llvmPackages;
    packages = selectFrom self;
  } // nixpkgs.lib.optionalAttrs useReflexOptimizer {
    ghcLibdir = "${self.ghc.bootPackages.ghcWithPackages (p: [ p.reflex ])}/lib/${self.ghc.bootPackages.ghc.name}";
  };

  ghcjs-base = doJailbreak (dontCheck (self.callCabal2nix "ghcjs-base" self._dep.ghcjsBaseSrc {}));
  # ghcjs-base needs an older version than nixpkgs provides.
  primitive = self.callHackage "primitive" "0.6.4.0" {};

  ghc = if !(lib.versionAtLeast super.ghc.ghcVersion "8.2") then super.ghc else super.ghc.overrideAttrs (_: {
    # TODO: I don't think this is needed except for maybe the fast-weak patch, but doing this to preserve hashes.
    phases = [ "unpackPhase" "patchPhase" "buildPhase" ];
  }) // {
    withPackages = self.ghcWithPackages;
  };

  # doctest doesn't work on ghcjs, but sometimes dontCheck doesn't seem to get rid of the dependency
  doctest = lib.warn "ignoring dependency on doctest" null;

  network = haskellLib.overrideCabal super.network (drv: {
    revision = null;
    editedCabalFile = null;
    patches = (drv.patches or []) ++ [ ./ghcjs-network.patch ];
  });

  # These packages require doctest
  comonad = dontCheck super.comonad;
  http-types = dontCheck super.http-types;
  lens = disableCabalFlag (disableCabalFlag (dontCheck super.lens) "test-properties") "test-doctests";
  pgp-wordlist = dontCheck super.pgp-wordlist;
  prettyprinter = dontCheck super.prettyprinter;
  semigroupoids = disableCabalFlag super.semigroupoids "doctests";
  these = dontCheck super.these;
  email-validate = dontCheck super.email-validate;

  # These tests are not expected to support ghcjs
  QuickCheck = dontCheck super.QuickCheck;
  temporary = dontCheck super.temporary;

  # Custom docs don't build with ghcjs
  # https://github.com/reflex-frp/reflex-platform/issues/631
  servant = haskellLib.overrideCabal super.servant (drv: {
    postInstall = "";
  });

  # These tests never complete
  tasty-quickcheck = dontCheck super.tasty-quickcheck;

  # Convenience: tests take long to finish
  megaparsec = dontCheck super.megaparsec;

  # Cross fix is working for iOS but not JS for some reason
  cabal-macosx = null;
}
