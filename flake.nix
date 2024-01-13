{
  description = "My template repository of rust project";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-23.11";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, crane, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };
        inherit (pkgs) lib;

        toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain;
        craneLib = (crane.mkLib pkgs).overrideToolchain toolchain;
        tsFileFilter = path: _type: builtins.match ".*ts$" path != null;
        src = lib.cleanSourceWith {
          src = craneLib.path ./.;
          filter = path: type: (tsFileFilter path type) || (craneLib.filterCargoSources path type);
        };

        octokit-webhooks = pkgs.fetchFromGitHub {
          owner = "octokit";
          repo = "webhooks";
          rev = "v7.3.1"; # WARN: this should be synced with github-webhook/Cargo.toml
          hash = "sha256-ckGVw5owHTv1h73LGan6mn4PZls4sNjRo/n+rrJHqe0=";
        };

        commonArgs = {
          inherit src;
          strictDeps = true;
          # Common arguments can be set here to avoid repeating them later
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = [
            # Add additional build inputs here
            pkgs.openssl
          ] ++ lib.optionals pkgs.stdenv.isDarwin [
            # Additional darwin specific inputs can be set here
            pkgs.libiconv
            pkgs.darwin.Security
            pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
          ];

          # Additional environment variables can be set directly
          CARGO_PROFILE = "dev";
          WEBHOOK_SCHEMA_DTS = "${octokit-webhooks}/payload-types/schema.d.ts";
        } // builtins.removeAttrs
          (craneLib.crateNameFromCargoToml {
            cargoToml = ./github-webhook/Cargo.toml;
          }) [ "version" ];

        # Build *just* the cargo dependencies, so we can reuse
        # all of that work (e.g. via cachix) when running in CI
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        # Build the actual crate itself, reusing the dependency
        # artifacts from above.
        build = craneLib.buildPackage (commonArgs // {
          inherit cargoArtifacts;
        });
      in
      {
        checks = {
          # Build the crate as part of `nix flake check` for convenience
          inherit build;

          # Run clippy (and deny all warnings) on the crate source,
          # again, resuing the dependency artifacts from above.
          #
          # Note that this is done as a separate derivation so that
          # we can block the CI if there are issues here, but not
          # prevent downstream consumers from building our crate by itself.
          clippy = craneLib.cargoClippy (commonArgs // {
            inherit cargoArtifacts;
            cargoClippyExtraArgs = "--all-targets -- --deny warnings";
          });

          doc = craneLib.cargoDoc (commonArgs // {
            inherit cargoArtifacts;
          });

          # Check formatting
          fmt = craneLib.cargoFmt commonArgs;
        };
        packages.default = build;

        apps.default = flake-utils.lib.mkApp {
          drv = build;
        };

        devShells.default = craneLib.devShell {
          # Inherit inputs from checks.
          checks = self.checks.${system};

          # Additional dev-shell environment variables can be set directly
          # MY_CUSTOM_DEVELOPMENT_VAR = "something else";

          # Extra inputs can be added here; cargo and rustc are provided by default.
          packages = [
            # pkgs.ripgrep
          ];
        };
      }
    );
}
