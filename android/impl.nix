env: with env;
let overrideAndroidCabal = package: overrideCabal package (drv: {
      preConfigure = (drv.preConfigure or "") + ''
        sed -i 's%^executable *\(.*\)$%executable lib\1.so\n  cc-options: -shared -fPIC\n  ld-options: -shared -Wl,--gc-sections,--version-script=${./haskellActivity.version},-u,Java_systems_obsidian_HaskellActivity_haskellStartMain,-u,hs_main\n  ghc-options: -shared -fPIC -threaded -no-hs-main -lHSrts_thr -lCffi -lm -llog%i' *.cabal
      '';
    });
    androidenv = nixpkgs.androidenv;
    #TODO: Keep the signing key for dev mode more consistent, e.g. in ~/.config/reflex-platform, so that the app can be reinstalled in-place
    addDeployScript = src: nixpkgs.runCommand "android-app" {
      inherit src;
      buildCommand = ''
        mkdir -p "$out/bin"
        cp -r "$src"/* "$out"
        substitute ${./deploy.sh} $out/bin/deploy \
          --subst-var-by coreutils ${nixpkgs.coreutils} \
          --subst-var-by adb ${androidenv.androidPkgs_9_0.platform-tools} \
          --subst-var-by java ${nixpkgs.openjdk11} \
          --subst-var-by out $out
        chmod +x "$out/bin/deploy"
      '';
      buildInputs = [ androidenv.androidPkgs_9_0.androidsdk ];
    } "";
    buildGradleApp = import ./build-gradle-app.nix {
      inherit (nixpkgs) stdenv jdk gnumake gawk file runCommand
                     which gradle fetchurl buildEnv;
      inherit androidenv;
    };
    inherit (nixpkgs.lib) splitString escapeShellArg mapAttrs attrNames concatStrings optionalString;
in {
  buildApp = args: with args; addDeployScript (buildGradleApp {
    inherit acceptAndroidSdkLicenses mavenDeps;
    buildDirectory = "./.";
    inherit gradleTask;
    keyAlias = releaseKey.keyAlias or null;
    keyAliasPassword = releaseKey.keyPassword or null;
    keyStore = releaseKey.storeFile or null;
    keyStorePassword = releaseKey.storePassword or null;
    name = applicationId;
    platformVersions = [ "29" ];
    release = false;
    src =
      let splitApplicationId = splitString "." applicationId;
          appSOs = mapAttrs (abiVersion: { myNixpkgs, myHaskellPackages }: {
            hsApp = overrideAndroidCabal (package myHaskellPackages);
            sharedLibs = runtimeSharedLibs myNixpkgs;
          }) {
            "arm64-v8a" = {
              myNixpkgs = nixpkgsCross.android.aarch64;
              myHaskellPackages = ghcAndroidAarch64;
            };
            "armeabi-v7a" = {
              myNixpkgs = nixpkgsCross.android.aarch32;
              myHaskellPackages = ghcAndroidAarch32;
            };
          };
          abiVersions = attrNames appSOs;
      in nixpkgs.runCommand "android-app" {
        buildGradle = builtins.toFile "build.gradle" (import ./build.gradle.nix {
          inherit applicationId version additionalDependencies releaseKey universalApk;
          googleServicesClasspath = optionalString (googleServicesJson != null)
            "classpath 'com.google.gms:google-services:4.3.3'";
          googleServicesPlugin = optionalString (googleServicesJson != null)
            "apply plugin: 'com.google.gms.google-services'";
        });
        androidManifestXml = builtins.toFile "AndroidManifest.xml" (import ./AndroidManifest.xml.nix {
          inherit applicationId version iconPath intentFilters services permissions activityAttributes usesCleartextTraffic;
        });
        stringsXml = builtins.toFile "strings.xml" (import ./strings.xml.nix {
          inherit displayName;
        });
        applicationMk = builtins.toFile "Application.mk" (import ./Application.mk.nix {
          inherit nixpkgs abiVersions;
        });
        javaSrc = nixpkgs.buildEnv {
          name = applicationId + "-java";
          paths = javaSources ++ [
            (ghcAndroidAarch64.android-activity.src + "/java") #TODO: Use output, not src
            (ghcAndroidAarch64.reflex-dom.src + "/java")
          ];
        };
        src = ./src;
        nativeBuildInputs = [ nixpkgs.rsync ];
        unpackPhase = "";
      } (''
          cp -r --no-preserve=mode "$src" "$out"
          mkdir -p "$out/src/main"
          cp -r --no-preserve=mode "$javaSrc" "$out/src/main/java"
          ln -s "$buildGradle" "$out/build.gradle"
          ln -s "$androidManifestXml" "$out/AndroidManifest.xml"
          mkdir -p "$out/res/values"
          ln -s "$stringsXml" "$out/res/values/strings.xml"
          mkdir -p "$out/jni"
          ln -s "$applicationMk" "$out/jni/Application.mk"
          ${optionalString (googleServicesJson != null) ''cp '${googleServicesJson}' "$out/google-services.json"''}
        '' + concatStrings (builtins.map (arch:
          let
            inherit (appSOs.${arch}) hsApp sharedLibs;
            sharedLibsCmd = concatStrings (map (libPath: ''
              local lib="${libPath}"
              if [ ! -f "$lib" ] ; then
                >&2 echo 'Error: library $lib not found'
                exit 1
              fi
              cp --no-preserve=mode "$lib" "$ARCH_LIB"
              '') sharedLibs);
          in ''
            {
              ARCH_LIB=$out/lib/${arch}
              mkdir -p $ARCH_LIB

              local exe="${hsApp}/bin/lib${executableName}.so"
              if [ ! -f "$exe" ] ; then
                >&2 echo 'Error: executable "${executableName}" not found'
                exit 1
              fi
              cp --no-preserve=mode "$exe" "$ARCH_LIB/libHaskellActivity.so"

              '' + sharedLibsCmd + ''
            }
        '') abiVersions) + ''
          rsync -r --chmod=+w "${assets}"/ "$out/assets/"
          rsync -r --chmod=+w "${resources}"/ "$out/res/"
          [ -d "$out/assets" ]
          [ -d "$out/res" ]
        '');
    useGooglePlayServices = true; # TODO: Should this be enabled by default?
    useGoogleAPIs = true; #TODO: Should this be enabled by default?

    # We use the NDK build process
    useNDK = true;
  });

  intentFilterXml = args: with args; ''
    <intent-filter android:autoVerify="true">
      <action android:name="android.intent.action.VIEW" />
      <category android:name="android.intent.category.DEFAULT" />
      <category android:name="android.intent.category.BROWSABLE" />
      <data android:scheme="${scheme}"
            android:host="${host}"
            ${ optionalString (port != null) ''android:port="${toString port}"'' }
            android:pathPrefix="${pathPrefix}" />
    </intent-filter>
  '';
}
