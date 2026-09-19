{
  description = "reproducible Electron builds with persistent source and cache storage";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      buildToolsLockfilePatch = pkgs.writeText "electron-build-tools-yarn-lock-v9.patch" ''
        diff --git a/yarn.lock b/yarn.lock
        --- a/yarn.lock
        +++ b/yarn.lock
        @@ -4,2 +4,2 @@
         __metadata:
        -  version: 8
        +  version: 9
      '';
      buildTools = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
        pname = "electron-build-tools";
        version = "0.2.0";

        src = pkgs.fetchFromGitHub {
          owner = "electron";
          repo = "build-tools";
          rev = "3f2c00792ab46cf9b9ab492a3f0a67c8f5d303be";
          hash = "sha256-wN2tCNpkNHtcjRblgqcUZledH0Jd1+GtWWFNzz9TMkQ=";
        };

        patches = [ buildToolsLockfilePatch ];
        missingHashes = ./config/build-tools-missing-hashes.json;
        offlineCache = pkgs.yarn-berry_4.fetchYarnBerryDeps {
          inherit (finalAttrs) src missingHashes patches;
          hash = "sha256-oStt+Uv7i/yVO+9mfnLtZtjiS+ENytCAoMHz1JEiYfc=";
        };

        nativeBuildInputs = [
          pkgs.nodejs_24
          pkgs.yarn-berry_4
          pkgs.yarn-berry_4.yarnBerryConfigHook
        ];

        buildPhase = ''
          runHook preBuild
          yarn build
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p "$out"
          cp -a dist src tools .yarn .yarnrc.yml node_modules package.json yarn.lock evm-config.schema.json "$out/"
          install -Dm755 /dev/stdin "$out/bin/e" <<'EOF'
          #!/bin/sh
          set -eu
          root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
          exec ${pkgs.nodejs_24}/bin/node "$root/src/e" "$@"
          EOF
          touch "$out/.disable-auto-updates"
          runHook postInstall
        '';
      });
      buildEnv = pkgs.buildFHSEnv {
        name = "electron-build";
        targetPkgs = pkgs: with pkgs; [
          alsa-lib atk at-spi2-atk at-spi2-core bashInteractive bison cacert
          cairo ccache clang cmake coreutils cups curl dbus expat file flex
          fontconfig freetype gcc git glib glibc gn gnumake gperf gtk3 jq
          libdrm libgbm libglvnd libnotify libpulseaudio libx11 libxcb
          libxcomposite libxcursor libxdamage libxext libxfixes libxi
          libxinerama libxkbcommon libxkbfile libxrandr libxrender libxshmfence
          libxscrnsaver libxt libxtst lld mesa ncurses5 ninja nodejs_24
          nspr nss pango patch pciutils perl pkg-config procps python3 just
          sccache sops age unzip util-linux wayland which xz zip zlib zstd awscli2
        ];
        runScript = "bash";
        profile = ''
          export COREPACK_HOME="$HOME/.cache/corepack"
          export ELECTRON_WORKSPACE="''${ELECTRON_WORKSPACE:-$HOME/.cache/electron-build}"
          export EVM_CONFIG="''${EVM_CONFIG:-$ELECTRON_WORKSPACE/config}"
          export DEPOT_TOOLS_DIR="''${DEPOT_TOOLS_DIR:-$ELECTRON_WORKSPACE/depot_tools}"
          export GIT_CACHE_PATH="''${GIT_CACHE_PATH:-$ELECTRON_WORKSPACE/git-cache}"
          export SCCACHE_DIR="''${SCCACHE_DIR:-$ELECTRON_WORKSPACE/sccache}"
          export AGREE_NOTGOMA_TOS=1
          export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          export NIX_SSL_CERT_FILE="$SSL_CERT_FILE"

          mkdir -p "$COREPACK_HOME" "$EVM_CONFIG" \
            "$ELECTRON_WORKSPACE" "$DEPOT_TOOLS_DIR" "$GIT_CACHE_PATH" "$SCCACHE_DIR"

          build_tools_root="$ELECTRON_WORKSPACE/build-tools"
          build_tools_revision="3f2c00792ab46cf9b9ab492a3f0a67c8f5d303be"
          if [[ ! -f "$build_tools_root/.electron-build-tools-revision" ]] || \
            [[ "$(<"$build_tools_root/.electron-build-tools-revision")" != "$build_tools_revision" ]]; then
            mkdir -p "$build_tools_root"
            cp -a "${buildTools}/." "$build_tools_root/"
            printf '%s\n' "$build_tools_revision" > "$build_tools_root/.electron-build-tools-revision"
          fi
          export ELECTRON_BUILD_TOOLS_ROOT="$build_tools_root"
          export PATH="$build_tools_root/bin:$PATH"

          printf '%s\n' \
            "Electron workspace: $ELECTRON_WORKSPACE" \
            "Run 'e d rbe login' when you need a fresh NotGoma credential."
        '';
      };
    in {
      packages.${system}.default = buildEnv;
      apps.${system}.default = {
        type = "app";
        program = "${buildEnv}/bin/electron-build";
        meta.description = "Electron build environment";
      };
      devShells.${system}.default = pkgs.mkShell {
        shellHook = ''exec ${buildEnv}/bin/electron-build'';
      };
    };
}
