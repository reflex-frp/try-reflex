{ haskellLib
, fetchFromGitHub
, nixpkgs
}:
with haskellLib;
let # Adds additional arguments to 'buildInputs' and the 'HASKELL_GI_GIR_SEARCH_PATH' environment variable
    # used by haskell-gi to specify non-standard locations .gir file locations
    # addGIDeps :: haskellPackage -> [nixPackage] -> [nixPackage] -> haskellPackage
    addGIDeps = p: extraBuildInputs: girSearchPathPackages: p.overrideAttrs (drv: {
      # cabal2nix puts these deps in libraryPkgconfigDepends but that doesn't seem to suffice.
      buildInputs = with nixpkgs; drv.buildInputs or [] ++ [ pkgconfig gobjectIntrospection ] ++ extraBuildInputs;
      libraryPkgconfigDepends = drv.libraryPkgconfigDepends or [] ++ [nixpkgs.gobject-introspection];
      # This preConfigure should have been added by cabal2nix according to this commit: https://github.com/NixOS/cabal2nix/commit/426fde8847370c32731a1db314283f5ebcbabeb7
      # though that functionality was removed in a later commit: https://github.com/NixOS/cabal2nix/commit/2d278a8a1527b278939ba478fe915aa2f87cc22e#diff-387ec31295a66a4f73b8d4b507a239a2
      # Cf. https://github.com/haskell-gi/haskell-gi/issues/36
      preConfigure = "export HASKELL_GI_GIR_SEARCH_PATH=" +
        nixpkgs.lib.concatStringsSep ":"
          (map (x: "${x.dev}/share/gir-1.0") ([nixpkgs.gobjectIntrospection] ++ girSearchPathPackages));
    });
in self: super: {

  # Recently uploaded to hackage:
  haven = self.callHackage "haven" "0.2.0.2" {};

  # Update hlint and add new dependency
  hlint = self.callHackage "hlint" "2.2.2" {};
  ghc-lib-parser = self.callHackage "ghc-lib-parser" "8.8.0.20190723" {};
  haskell-src-exts-util = self.callHackage "haskell-src-exts-util" "0.2.5" {};
  stylish-haskell = self.callHackage "stylish-haskell" "0.9.2.2" {};

  # Fixing things that are marked broken in 19.03:
  butcher = doJailbreak (self.callHackage "butcher" "1.3.2.3" {});
  multistate = self.callHackage "multistate" "0.8.0.2" {};
  haddock-api = dontHaddock (doJailbreak (self.callHackage "haddock-api" "2.22.0" {}));
  constrained-dynamic = self.callHackage "constrained-dynamic" "0.1.0.0" {};
  hsimport = doJailbreak (self.callHackage "hsimport" "0.10.0" {});
  webkit2gtk3-javascriptcore = self.callHackage "webkit2gtk3-javascriptcore" "0.14.2.1" {};

  # Snap and deps are marked broken in 19.03 but needed by obelisk
  snap = self.callHackage "snap" "1.1.2.0" {};
  heist = dontCheck (self.callHackage "heist" "1.1.0.1" {});
  map-syntax = doJailbreak (self.callHackage "map-syntax" "0.3" {});

  # Fixing things that are marked broken in 19.09:
  brittany = dontCheck (self.callHackage "brittany" "0.12.0.0" {});
  witherable = self.callHackage "witherable" "0.3.1" {};
  time-compat = dontCheck super.time-compat;
  bimap = self.callHackage "bimap" "0.3.3" {};

  # Overrides for gi-* family of libraries. See addGIDeps, above.
  haskell-gi-base = addGIDeps (super.haskell-gi-base) [nixpkgs.glib] [];
  gi-glib = addGIDeps (super.gi-glib) [] [];
  gi-cairo = addGIDeps (super.gi-cairo) [nixpkgs.cairo] [];
  gi-gobject = addGIDeps (super.gi-gobject) [] [];
  gi-pango = addGIDeps (super.gi-pango) [nixpkgs.pango] [];
  gi-gio = addGIDeps (super.gi-gio) [] [];
  gi-atk = addGIDeps (super.gi-atk) [] [];
  gi-javascriptcore = addGIDeps (super.gi-javascriptcore) [] [];
  gi-gdkpixbuf = addGIDeps (super.gi-gdkpixbuf) [nixpkgs.gdk_pixbuf nixpkgs.gtk3] [nixpkgs.gtk3];
  gi-gdk = addGIDeps (super.gi-gdk) [nixpkgs.gdk_pixbuf nixpkgs.pango nixpkgs.gtk3] [nixpkgs.gtk3];
  gi-soup = addGIDeps (super.gi-soup) [nixpkgs.gdk_pixbuf] [nixpkgs.libsoup];
  gi-gtk = addGIDeps (super.gi-gtk) [nixpkgs.gdk_pixbuf nixpkgs.gtk3] [nixpkgs.gtk3 nixpkgs.atk nixpkgs.pango];
  gi-webkit2 = addGIDeps (super.gi-webkit2) [] [nixpkgs.webkitgtk];

  # Required by butcher
  deque = self.callHackage "deque" "0.4.2.3" {};
  strict-list = self.callHackage "strict-list" "0.1.4" {};

  # These take over an hour to run, each
  cryptonite = dontCheck super.cryptonite;
  scientific = dontCheck super.scientific;

  # Packages not yet in 19.03
  semialign = self.callHackage "semialign" "1.1" {};
  these = self.callHackage "these" "1.0.1" {};
  semialign-indexed = self.callHackage "semialign-indexed" "1.1" {}; # to work with semialign 1.1
  these-lens = doJailbreak (self.callHackage "these-lens" "1" {});
  # remove jailbreak after https://github.com/isomorphism/these/pull/134

  # Broken in 19.09
  http-streams = doJailbreak (self.callHackage "http-streams" "0.8.6.1" {});

  # pandoc 2.11 and dependencies
  commonmark = self.callHackage "commonmark" "0.1.0.2" {};
  commonmark-extensions = self.callHackage "commonmark-extensions" "0.2.0.1" {};
  commonmark-pandoc = self.callHackage "commonmark-pandoc" "0.2.0.1" {};
  citeproc = doJailbreak (self.callHackage "citeproc" "0.1.0.2" {});
  emojis = self.callHackage "emojis" "0.1" {};
  jira-wiki-markup = self.callHackage "jira-wiki-markup" "1.3.2" {};
  pandoc = self.callHackage "pandoc" "2.11.0.2" {};
  pandoc-types = self.callHackage "pandoc-types" "1.22" {};
  texmath = self.callHackage "texmath" "0.12.0.3" {};
  rfc5051 = self.callHackage "rfc5051" "0.2" {};
  HsYAML = self.callHackage "HsYAML" "0.2.1.0" {};
  connection = self.callHackage "connection" "0.3.1" {};
  doclayout = self.callHackage "doclayout" "0.3" {};
  doctemplates = self.callHackage "doctemplates" "0.8.2" {};
  haddock-library = doJailbreak (self.callHackage "haddock-library" "1.8.0" {});
  hslua  = self.callHackage "hslua" "1.1.0" {};
  skylighting = self.callHackage "skylighting" "0.10.0.2" {};
  skylighting-core = self.callHackage "skylighting-core" "0.10.0.2" {};

  # beam packages
  beam-core = self.callHackage "beam-core" "0.9.0.0" {};
  beam-migrate = self.callHackage "beam-migrate" "0.5.0.0" {};
  beam-postgres = haskellLib.dontCheck (self.callHackage "beam-postgres" "0.5.0.0" {});
  beam-automigrate = self.callHackage "beam-automigrate" "0.1.0.0" {};

  # hnix 0.12 and dependencies
  hnix = dontCheck
    (overrideCabal (self.callCabal2nix "hnix" (nixpkgs.hackGet ./hnix/hnix) {}) (drv: {
      librarySystemDepends = (drv.librarySystemDepends or []) ++ [ nixpkgs.nix ];
      testHaskellDepends = (drv.testHaskellDepends or []) ++ [ nixpkgs.nix super.criterion ];
    }));
  hnix-store-core =
    self.callCabal2nix "hnix" (nixpkgs.hackGet ./hnix/hnix-store + "/hnix-store-core") {};
  hnix-store-remote =
    self.callCabal2nix "hnix" (nixpkgs.hackGet ./hnix/hnix-store + "/hnix-store-remote") {};
  algebraic-graphs = self.callHackage "algebraic-graphs" "0.5" {};
  nix-derivation = self.callHackage "nix-derivation" "1.1.1" {};
  data-fix = self.callHackage "data-fix" "0.3.0" {};
  neat-interpolation = self.callHackage "neat-interpolation" "0.5.1.2" {};
  prettyprinter = self.callHackage "prettyprinter" "1.7.0" {};

}
