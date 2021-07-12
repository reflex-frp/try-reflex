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
    nixpkgs2003 = import ../nixpkgs-20.03 {};
in self: super: {

  # Need an older version for GHC 8.6
  haddock-api = dontHaddock (doJailbreak (self.callHackage "haddock-api" "2.22.0" {}));
  # TODO this conflicts with the pandoc version
  # haddock-library = doJailbreak (self.callHackage "haddock-library" "1.7.0" {});

  # Fixing things that are marked broken in 20.09:
  constrained-dynamic = dontCheck (markUnbroken super.constrained-dynamic);
  haven = markUnbroken super.haven;

  # Overrides for gi-* family of libraries. See addGIDeps, above.
  # Also use an older version suitable for GHC 8.6, because haskell-gi-base ==
  # 0.24.2 needs a newer compiler. https://github.com/haskell-gi/haskell-gi/issues/304
  # We also need nixpkgs2003 for older gi* deps. TODO: This should be removed
  # after GHC is bumped, and the uses of (callHackage "x") can be switched back
  # to (super.x).
  haskell-gi-base = addGIDeps (self.callHackage "haskell-gi-base" "0.23.0" {}) [nixpkgs.glib] [];
  haskell-gi = addGIDeps (self.callHackage "haskell-gi" "0.23.0" {}) [] [];
  gi-glib = addGIDeps (self.callHackage "gi-glib" "2.0.23" {}) [] [];
  gi-cairo = addGIDeps (self.callHackage "gi-cairo" "1.0.23" {}) [nixpkgs.cairo] [];
  gi-gobject = addGIDeps (self.callHackage "gi-gobject" "2.0.22" {}) [] [];
  gi-pango = addGIDeps (self.callHackage "gi-pango" "1.0.22" {}) [nixpkgs2003.pango] [];
  gi-gio = addGIDeps (self.callHackage "gi-gio" "2.0.25" {}) [] [];
  gi-atk = addGIDeps (self.callHackage "gi-atk" "2.0.21" {}) [] [];
  gi-javascriptcore = addGIDeps (self.callHackage "gi-javascriptcore" "4.0.21" {}) [] [];
  gi-gdkpixbuf = addGIDeps (self.callHackage "gi-gdkpixbuf" "2.0.23" {}) [nixpkgs2003.gdk_pixbuf nixpkgs2003.gtk3] [nixpkgs2003.gtk3];
  gi-gdk = addGIDeps (self.callHackage "gi-gdk" "3.0.22" {}) [nixpkgs2003.gdk_pixbuf nixpkgs2003.pango nixpkgs2003.gtk3] [nixpkgs2003.gtk3];
  gi-soup = addGIDeps (self.callHackage "gi-soup" "2.4.22" {}) [nixpkgs2003.gdk_pixbuf] [nixpkgs2003.libsoup];
  gi-gtk = addGIDeps (self.callHackage "gi-gtk" "3.0.32" {}) [nixpkgs2003.gdk_pixbuf nixpkgs2003.gtk3] [nixpkgs2003.gtk3 nixpkgs2003.atk nixpkgs2003.pango];
  gi-webkit2 = addGIDeps (self.callHackage "gi-webkit2" "4.0.25" {}) [] [nixpkgs2003.webkitgtk];

  # These take over an hour to run, each
  cryptonite = dontCheck super.cryptonite;
  scientific = dontCheck super.scientific;

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
  data-fix = self.callHackage "data-fix" "0.3.0" {};
  neat-interpolation = self.callHackage "neat-interpolation" "0.4" {};
  prettyprinter = self.callHackage "prettyprinter" "1.7.0" {};

}
