{ nixpkgsFunc ? import ./nixpkgs
, system ? builtins.currentSystem
, config ? {}
, enableLibraryProfiling ? false
, enableExposeAllUnfoldings ? true
, enableTraceReflexEvents ? false
, useFastWeak ? true
, useReflexOptimizer ? false
, useTextJSString ? true # Use an implementation of "Data.Text" that uses the more performant "Data.JSString" from ghcjs-base under the hood.
, __useTemplateHaskell ? true # Deprecated, just here until we remove feature from reflex and stop CIing it
, iosSdkVersion ? "13.2"
, nixpkgsOverlays ? []
, haskellOverlays ? [] # TODO deprecate
, haskellOverlaysPre ? []
, haskellOverlaysPost ? haskellOverlays
, hideDeprecated ? false # The moral equivalent of "-Wcompat -Werror" for using reflex-platform.
, hlsSupport ? false
}:
let iosSupport = system == "x86_64-darwin";
    androidSupport = lib.elem system [ "x86_64-linux" ];

    xcodeVer = {
      "13.2" = "11.3.1";
    }.${iosSdkVersion} or (throw "Unknown iosSdkVersion: ${iosSdkVersion}");

    # Overlay for GHC with -load-splices & -save-splices option
    splicesEval = self: super: {
      haskell = super.haskell // {
        compiler = super.haskell.compiler // {
          ghcSplices-8_6 = super.haskell.compiler.ghc865.overrideAttrs (drv: {
            enableParallelBuilding = false;
            src = nixpkgs.hackGet ./haskell-overlays/splices-load-save/dep/ghc;
            # When building from the ghc git repo, ./boot must be run before configuring, whereas
            # in the distribution tarball on the haskell.org downloads page, ./boot has already been
            # run.
            preConfigure= ''
              echo ${drv.version} >VERSION
              ./boot
            '' + drv.preConfigure or "";
            # Our fork of 8.6 with splices includes these patches.
            # Specifically, is up to date with the `ghc-8.6` branch upstream,
            # which contains various backports for any potential newer 8.6.x
            # release. Nixpkgs manually applied some of those backports as
            # patches onto 8.6.5 ahead of such a release, but now we get them
            # from the src proper.
            patches = [];
          });
        };
        packages = super.haskell.packages // {
          ghcSplices-8_6 = super.haskell.packages.ghc865.override {
            buildHaskellPackages = self.buildPackages.haskell.packages.ghcSplices-8_6;
            ghc = self.buildPackages.haskell.compiler.ghcSplices-8_6;
          };
        };
      };
    };

    hackGetOverlay = self: super:
      import ./nixpkgs-overlays/hack-get { inherit lib; } self;

    bindHaskellOverlays = self: super: {
      haskell = super.haskell // {
        overlays = super.haskell.overlays or {} // import ./haskell-overlays {
          nixpkgs = self;
          inherit (self) lib;
          haskellLib = self.haskell.lib;
          inherit
            useFastWeak useReflexOptimizer enableLibraryProfiling enableTraceReflexEvents
            useTextJSString enableExposeAllUnfoldings __useTemplateHaskell
            haskellOverlaysPre
            haskellOverlaysPost;
          inherit ghcSavedSplices;
        };
      };
    };

    forceStaticLibs = self: super: {
      darwin = super.darwin // {
        libiconv = super.darwin.libiconv.overrideAttrs (_:
          lib.optionalAttrs (self.stdenv.hostPlatform != self.stdenv.buildPlatform) {
            postInstall = "rm $out/include/libcharset.h $out/include/localcharset.h";
            configureFlags = ["--disable-shared" "--enable-static"];
          });
      };
      zlib = super.zlib.override (lib.optionalAttrs
        (self.stdenv.hostPlatform != self.stdenv.buildPlatform)
        { static = true; shared = false; });
    };

    mobileGhcOverlay = import ./nixpkgs-overlays/mobile-ghc { inherit lib; };

    allCabalHashesOverlay = import ./nixpkgs-overlays/all-cabal-hashes;

    nixpkgsArgs = {
      inherit system;
      overlays = [
        hackGetOverlay
        bindHaskellOverlays
        forceStaticLibs
        splicesEval
        mobileGhcOverlay
        allCabalHashesOverlay
        (import ./nixpkgs-overlays/ghc.nix { inherit lib; })
      ] ++ nixpkgsOverlays;
      config = {
        permittedInsecurePackages = [
          "webkitgtk-2.4.11"
        ];

        # XCode needed for native macOS app
        # Obelisk needs it to for some reason
        allowUnfree = true;
      } // config;
    };

    nixpkgs = nixpkgsFunc nixpkgsArgs;

    inherit (nixpkgs) lib fetchurl fetchgit fetchgitPrivate fetchFromGitHub fetchFromBitbucket;

    wasmCross = nixpkgs.hackGet ./wasm-cross;
    webGhcSrc = (import (wasmCross + /webghc.nix) { inherit fetchgit; }).ghc865SplicesSrc;
    nixpkgsCross = {
      android = lib.mapAttrs (_: args: nixpkgsFunc (nixpkgsArgs // args)) rec {
        aarch64 = {
          crossSystem = lib.systems.examples.aarch64-android-prebuilt;
        };
        aarch32 = {
          crossSystem = lib.systems.examples.armv7a-android-prebuilt // {
            # Hard to find newer 32-bit phone to test with that's newer than
            # this. Concretely, doing so resulted in:
            # https://android.googlesource.com/platform/bionic/+/master/libc/arch-common/bionic/pthread_atfork.h#19
            sdkVer = "22";
          };
        };
      };
      ios = lib.mapAttrs (_: args: nixpkgsFunc (nixpkgsArgs // args)) rec {
        simulator64 = {
          crossSystem = lib.systems.examples.iphone64-simulator // {
            sdkVer = iosSdkVersion;
            inherit xcodeVer;
          };
        };
        aarch64 = {
          crossSystem = lib.systems.examples.iphone64 // {
            sdkVer = iosSdkVersion;
            inherit xcodeVer;
          };
        };
        aarch32 = {
          crossSystem = lib.systems.examples.iphone32 // {
            sdkVer = iosSdkVersion;
            inherit xcodeVer;
          };
        };
        # Back compat
        arm64 = lib.warn "nixpkgsCross.ios.arm64 has been deprecated, using nixpkgsCross.ios.aarch64 instead." aarch64;
      };
      ghcjs = nixpkgsFunc (nixpkgsArgs // {
        crossSystem = lib.systems.examples.ghcjs;
      });
      wasm = nixpkgsFunc (nixpkgsArgs //
        (import wasmCross { inherit nixpkgsFunc; }).nixpkgsCrossArgs webGhcSrc "8.6.5"
      );
    };

    haskellLib = nixpkgs.haskell.lib;

    overrideCabal = pkg: f: if pkg == null then null else haskellLib.overrideCabal pkg f;

    combineOverrides = old: new: old // new // lib.optionalAttrs (old ? overrides && new ? overrides) {
      overrides = lib.composeExtensions old.overrides new.overrides;
    };

    # Makes sure that old `overrides` from a previous call to `override` are not
    # forgotten, but composed. Do this by overriding `override` and passing a
    # function which takes the old argument set and combining it. What a tongue
    # twister!
    makeRecursivelyOverridable = x: x // {
      override = new: makeRecursivelyOverridable (x.override (old: (combineOverrides old new)));
    };

    cabal2nixResult = src: builtins.trace "cabal2nixResult is deprecated; use ghc.haskellSrc2nix or ghc.callCabal2nix instead" (ghc.haskellSrc2nix {
      name = "for-unknown-package";
      src = "file://${src}";
      sha256 = null;
    });

  ghcSavedSplices = ghcSavedSplices-8_6;
  ghcSavedSplices-8_6 = (makeRecursivelyOverridable nixpkgs.haskell.packages.integer-simple.ghcSplices-8_6).override {
    overrides = lib.foldr lib.composeExtensions (_: _: {}) (let
      haskellOverlays = nixpkgs.haskell.overlays;
    in [
      haskellOverlays.combined
      haskellOverlays.saveSplices
      (self: super: with haskellLib; {
        blaze-textual = haskellLib.enableCabalFlag super.blaze-textual "integer-simple";
        cryptonite = disableCabalFlag super.cryptonite "integer-gmp";
        integer-logarithms = disableCabalFlag super.integer-logarithms "integer-gmp";
        scientific = enableCabalFlag super.scientific "integer-simple";
        dependent-sum-template = dontCheck super.dependent-sum-template;
        generic-deriving = dontCheck super.generic-deriving;
      })
    ]);
  };
  ghcjs = ghcjs8_6;
  ghcjs8_6 = (makeRecursivelyOverridable (nixpkgsCross.ghcjs.haskell.packages.ghcjs86.override (old: {
    ghc = old.ghc.override {
      bootPkgs = nixpkgsCross.ghcjs.buildPackages.haskell.packages.ghc865;
      ghcjsSrc = fetchgit {
        url = "https://github.com/obsidiansystems/ghcjs.git";
        rev = "a00ecf0b2eaddbc4101c76e6ac95fc97b0f75840"; # ghc-8.6 branch
        sha256 = "06cwpijwhj4jpprn07y3pkxmv40pwmqqw5jbdv4s7c67j5pmirnc";
        fetchSubmodules = true;
      };
    };
  }))).override {
    overrides = nixpkgsCross.ghcjs.haskell.overlays.combined;
  };

  wasm = ghcWasm32-8_6;
  ghcWasm32-8_6 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable (nixpkgsCross.wasm.haskell.packages.ghcWasm.override (old: {
    # Due to the splices changes the parallel build fails while building the libraries
    ghc = old.ghc.overrideAttrs (drv: { enableParallelBuilding = false; });
  }))).override {
    overrides = nixpkgsCross.wasm.haskell.overlays.combined;
  });

  ghc = ghc8_6;
  ghcHEAD = (makeRecursivelyOverridable nixpkgs.haskell.packages.ghcHEAD).override {
    overrides = nixpkgs.haskell.overlays.combined;
  };
  ghc8_6 = (makeRecursivelyOverridable nixpkgs.haskell.packages.ghc865).override {
    overrides = nixpkgs.haskell.overlays.combined;
  };

  # Takes a package set with `makeRecursivelyOverridable` and ensures that any
  # future overrides will be applied to both the package set itself and it's
  # build-time package set (`buildHaskellPackages`).
  makeRecursivelyOverridableBHPToo = x: x // {
    override = new: makeRecursivelyOverridableBHPToo (x.override
      (combineOverrides
        {
          overrides = self: super: {
            buildHaskellPackages = super.buildHaskellPackages.override new;
          };
        }
        new));
  };

  ghcAndroidAarch64 = ghcAndroidAarch64-8_6;
  ghcAndroidAarch64-8_6 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.android.aarch64.haskell.packages.integer-simple.ghcSplices-8_6).override {
    overrides = nixpkgsCross.android.aarch64.haskell.overlays.combined;
  });
  ghcAndroidAarch32 = ghcAndroidAarch32-8_6;
  ghcAndroidAarch32-8_6 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.android.aarch32.haskell.packages.integer-simple.ghcSplices-8_6).override {
    overrides = nixpkgsCross.android.aarch32.haskell.overlays.combined;
  });

  ghcIosSimulator64 = ghcIosSimulator64-8_6;
  ghcIosSimulator64-8_6 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.ios.simulator64.haskell.packages.integer-simple.ghcSplices-8_6).override {
    overrides = nixpkgsCross.ios.simulator64.haskell.overlays.combined;
  });
  ghcIosAarch64 = ghcIosAarch64-8_6;
  ghcIosAarch64-8_6 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.ios.aarch64.haskell.packages.integer-simple.ghcSplices-8_6).override {
    overrides = nixpkgsCross.ios.aarch64.haskell.overlays.combined;
  });
  ghcIosAarch32 = ghcIosAarch32-8_6;
  ghcIosAarch32-8_6 = makeRecursivelyOverridableBHPToo ((makeRecursivelyOverridable nixpkgsCross.ios.aarch32.haskell.packages.integer-simple.ghcSplices-8_6).override {
    overrides = nixpkgsCross.ios.aarch32.haskell.overlays.combined;
  });

  #TODO: Separate debug and release APKs
  #TODO: Warn the user that the android app name can't include dashes
  android = androidWithHaskellPackages {
    inherit ghcAndroidAarch64 ghcAndroidAarch32;
  };
  android-8_6 = androidWithHaskellPackages {
    ghcAndroidAarch64 = ghcAndroidAarch64-8_6;
    ghcAndroidAarch32 = ghcAndroidAarch32-8_6;
  };
  androidWithHaskellPackages = { ghcAndroidAarch64, ghcAndroidAarch32 }: import ./android {
    inherit nixpkgs nixpkgsCross ghcAndroidAarch64 ghcAndroidAarch32 overrideCabal;
    acceptAndroidSdkLicenses = config.android_sdk.accept_license or false;
  };
  iosAarch64 = iosWithHaskellPackages ghcIosAarch64;
  iosAarch64-8_6 = iosWithHaskellPackages ghcIosAarch64-8_6;
  iosAarch32 = iosWithHaskellPackages ghcIosAarch32;
  iosAarch32-8_6 = iosWithHaskellPackages ghcIosAarch32-8_6;
  iosSimulator = {
    buildApp = nixpkgs.lib.makeOverridable (import ./ios { inherit nixpkgs; ghc = ghcIosSimulator64; withSimulator = true; });
  };
  iosWithHaskellPackages = ghc: {
    buildApp = nixpkgs.lib.makeOverridable (import ./ios { inherit nixpkgs ghc; });
  };

in let this = rec {
  inherit (nixpkgs)
    filterGit
    hackGet
    thunkSet
    ;
  inherit nixpkgs
          nixpkgsCross
          overrideCabal
          ghc
          ghcHEAD
          ghc8_6
          ghcIosSimulator64
          ghcIosAarch64
          ghcIosAarch64-8_6
          ghcIosAarch32
          ghcIosAarch32-8_6
          ghcAndroidAarch64
          ghcAndroidAarch64-8_6
          ghcAndroidAarch32
          ghcAndroidAarch32-8_6
          ghcjs
          ghcjs8_6
          ghcSavedSplices
          android
          androidWithHaskellPackages
          iosAarch32
          iosAarch64
          iosSimulator
          iosWithHaskellPackages
          wasm
          wasmCross
          ;

  # Back compat
  ios = iosAarch64;
  ghcAndroidArm64 = lib.warn "ghcAndroidArm64 has been deprecated, using ghcAndroidAarch64 instead." ghcAndroidAarch64;
  ghcAndroidArmv7a = lib.warn "ghcAndroidArmv7a has been deprecated, using ghcAndroidAarch32 instead." ghcAndroidAarch32;
  ghcIosArm64 = lib.warn "ghcIosArm64 has been deprecated, using ghcIosAarch64 instead." ghcIosAarch64;

  androidReflexTodomvc = android.buildApp {
    package = p: p.reflex-todomvc;
    executableName = "reflex-todomvc";
    applicationId = "org.reflexfrp.todomvc";
    displayName = "Reflex TodoMVC";
  };
  androidReflexTodomvc-8_6 = android-8_6.buildApp {
    package = p: p.reflex-todomvc;
    executableName = "reflex-todomvc";
    applicationId = "org.reflexfrp.todomvc.via_8_6";
    displayName = "Reflex TodoMVC via GHC 8.6";
  };
  iosReflexTodomvc = ios.buildApp {
    package = p: p.reflex-todomvc;
    executableName = "reflex-todomvc";
    bundleIdentifier = "org.reflexfrp.todomvc";
    bundleName = "Reflex TodoMVC";
  };
  iosReflexTodomvc-8_6 = iosAarch64-8_6.buildApp {
    package = p: p.reflex-todomvc;
    executableName = "reflex-todomvc";
    bundleIdentifier = "org.reflexfrp.todomvc.via_8_6";
    bundleName = "Reflex TodoMVC via GHC 8.6";
  };
  iosSimulatorReflexTodomvc = iosSimulator.buildApp {
    package = p: p.reflex-todomvc;
    executableName = "reflex-todomvc";
    bundleIdentifier = "org.reflexfrp.todomvc";
    bundleName = "Reflex TodoMVC";
  };
  setGhcLibdir = ghcLibdir: inputGhcjs:
    let libDir = "$out/lib/ghcjs-${inputGhcjs.version}";
        ghcLibdirLink = nixpkgs.stdenv.mkDerivation {
          name = "ghc_libdir";
          inherit ghcLibdir;
          buildCommand = ''
            mkdir -p ${libDir}
            echo "$ghcLibdir" > ${libDir}/ghc_libdir_override
          '';
        };
    in inputGhcjs // {
    outPath = nixpkgs.buildEnv {
      inherit (inputGhcjs) name;
      paths = [ inputGhcjs ghcLibdirLink ];
      postBuild = ''
        mv ${libDir}/ghc_libdir_override ${libDir}/ghc_libdir
      '';
    };
  };

  platforms = [
    "ghcjs"
    "ghc"
  ];

  androidDevTools = [
    ghc.haven
    nixpkgs.maven
    nixpkgs.androidsdk_9_0
  ];

  # Tools that are useful for development under both ghc and ghcjs
  generalDevTools' = { nativeHaskellPackages ? ghc }: {
    inherit (nativeHaskellPackages)
      Cabal
      cabal-install
      ghcid
      hasktags
      hdevtools
      hlint
      stylish-haskell # Recent stylish-haskell only builds with AMP in place
      reflex-ghci
      ;
    inherit (nixpkgs)
      cabal2nix
      curl
      nix-prefetch-scripts
      nodejs
      pkgconfig
      closurecompiler
      ;
  } // lib.optionalAttrs hlsSupport {
    haskell-language-server = nixpkgs.haskell.lib.justStaticExecutables (nativeHaskellPackages.override {
      overrides = nixpkgs.haskell.overlays.haskell-language-server;
    }).haskell-language-server;
  };

  workOn = haskellPackages: package: (overrideCabal package (drv: {
    buildTools = (drv.buildTools or []) ++ builtins.attrValues (generalDevTools' {});
  })).env;

  # A minimal wrapper around the build-wasm-app from wasm-cross
  # Useful in building simple cabal projects like reflex-todomvc
  build-wasm-app-wrapper =
    ename: # Name of the executable, usually same as cabal project name
    pkgPath : # Path of cabal package
    args: # Others options to pass to build-wasm-app
  let
    pkg = wasm.callPackage pkgPath {};
    webabi = nixpkgs.callPackage (wasmCross + /webabi) {};
    build-wasm-app = nixpkgs.callPackage (wasmCross + /build-wasm-app.nix) ({ inherit webabi; } // args);
  in build-wasm-app {
    inherit pkg ename;
  };

  # A simple derivation that just creates a file with the names of all
  # of its inputs. If built, it will have a runtime dependency on all
  # of the given build inputs.
  pinBuildInputs = name: buildInputs: (nixpkgs.releaseTools.aggregate {
    inherit name;
    constituents = buildInputs;
  }).overrideAttrs (old: {
    buildCommand = old.buildCommand + ''
      echo "$propagatedBuildInputs $buildInputs $nativeBuildInputs $propagatedNativeBuildInputs" > "$out/deps"
    '';
    inherit buildInputs;
  });

  reflexEnv = platform:
    let haskellPackages = builtins.getAttr platform this;
        ghcWithStuff = if platform == "ghc" || platform == "ghcjs"
                       then haskellPackages.ghcWithHoogle
                       else haskellPackages.ghcWithPackages;
    in ghcWithStuff (p: import ./packages.nix {
      haskellPackages = p;
      inherit platform;
    });

  tryReflexPackages = builtins.attrValues (generalDevTools' {})
    ++ builtins.map reflexEnv platforms;

  cachePackages =
    let otherPlatforms = lib.optionals androidSupport [
          "ghcAndroidAarch64"
          "ghcAndroidAarch32"
        ] ++ lib.optionals iosSupport [
          "ghcIosAarch64"
          "ghcIosSimulator64"
        ];
    in tryReflexPackages
      ++ builtins.map reflexEnv otherPlatforms
      ++ lib.optionals androidSupport [
        androidDevTools
        androidReflexTodomvc
      ] ++ lib.optionals iosSupport [
        iosReflexTodomvc iosSimulatorReflexTodomvc
      ];

  inherit cabal2nixResult system androidSupport iosSupport;
  project = args: import ./project this (args ({ pkgs = nixpkgs; } // this));
  tryReflexShell = pinBuildInputs ("shell-" + system) tryReflexPackages;
  ghcjsExternsJs = ./ghcjs.externs.js;
};

# Deprecated reexports. These were made for `./scripts/*`, but are reexported
# here for backwards compatability.
legacy = {
  # Added 2019-12, will be removed 2020-06.
  inherit
    (import ./nix-utils/hackage { reflex-platform = this; })
    attrsToList
    mapSet
    mkSdist
    sdists
    mkHackageDocs
    hackageDocs
    mkReleaseCandidate
    releaseCandidates
    ;
  generalDevTools = _: builtins.attrValues (this.generalDevTools' {});
  generalDevToolsAttrs = _: this.generalDevTools' {};
  nativeHaskellPackages = haskellPackages:
    if haskellPackages.isGhcjs or false
    then haskellPackages.ghc
    else haskellPackages;
  workOnMulti' = { env, packageNames }:
    (import ./nix-utils/work-on-multi {}).workOnMulti {
      envFunc = _: env;
      inherit packageNames;
    };
  workOnMulti = env: packageNames: legacy.workOnMulti' { inherit env packageNames; };
};

in this // lib.optionalAttrs
  (!hideDeprecated)
  (lib.mapAttrs (attrName: builtins.trace "The attribute \"${attrName}\" is deprecated. See reflex-platform's root default.nix.") legacy)
