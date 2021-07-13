{ lib }:

let # Setting libffi to null causes GHC to use its own vendored libffi, which seems to be
    # necessary on android. See discussion here:
    # https://github.com/reflex-frp/reflex-platform/pull/506#issuecomment-511978967
    overrideLibffiOnAndroid = self: v: if self.stdenv.targetPlatform.useAndroidPrebuilt
      then v.override { libffi = null; }
      else v;
in self: super: {
  haskell = super.haskell // {
    compiler = super.haskell.compiler // lib.mapAttrs (n: v: (overrideLibffiOnAndroid self v).overrideAttrs (drv: {
      patches = (drv.patches or []) ++ lib.optionals self.stdenv.targetPlatform.useAndroidPrebuilt [
        ./8.6.y/android-patches/force-relocation.patch
      ];
    })) { inherit (super.haskell.compiler) ghc8104 ghc8104Splices; };
  };
}
