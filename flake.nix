{
  description = "Bath Royale development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux";

    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        android_sdk.accept_license = true;
      };
    };

    androidComposition = pkgs.androidenv.composeAndroidPackages {
      platformVersions = ["35" "36"];
      buildToolsVersions = ["36.0.0"];

      includeNDK = true;
      ndkVersions = ["28.2.13676358"];

      includeEmulator = false;
      includeSystemImages = false;
      includeCmake = true;
      cmakeVersions = ["3.22.1"];
    };

    androidSdk = androidComposition.androidsdk;
    androidHome = "${androidSdk}/libexec/android-sdk";
  in {
    devShells.${system} = {
      # Optional backend evaluation tools; this does not enable a container service.
      backend = pkgs.mkShell {
        packages = with pkgs; [
          supabase-cli
          postgresql_17
          podman
          podman-compose
          python3
          ruff
        ];
      };

      default = (pkgs.mkShell.override {stdenv = pkgs.clangStdenv;}) {
        packages = with pkgs; [
          flutter
          cmake
          ninja
          pkg-config
          actionlint

          # Android development
          androidSdk
          jdk17
        ];

        buildInputs = with pkgs; [
          gtk3
          libsecret
          glib
        ];

        ANDROID_HOME = androidHome;
        ANDROID_SDK_ROOT = androidHome;
        ANDROID_NDK_ROOT = "${androidHome}/ndk/28.2.13676358";

        JAVA_HOME = "${pkgs.jdk17}";

        GRADLE_OPTS = "-Dorg.gradle.project.android.aapt2FromMavenOverride=${androidHome}/build-tools/36.0.0/aapt2";
      };
    };
  };
}
