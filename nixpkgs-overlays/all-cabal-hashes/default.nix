self: _: {

  all-cabal-hashes = self.fetchurl {
    url = https://github.com/commercialhaskell/all-cabal-hashes/archive/05301ee6f2076533bdd2a6b1f0c26d2912f1fe4d.tar.gz;
    sha256 = "1v43gg0pm8mr20n5ifh4hgwvxya71rmipfi291wj0hhwssy6zkq2";
  };

}
