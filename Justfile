set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load := false

default:
    @just --list

build major:
    @scripts/build {{ major }}

build-local major:
    @ELECTRON_BUILD_NO_REMOTE=1 scripts/build {{ major }}

update-build-tools ref:
    @python3 scripts/update-build-tools.py {{ ref }}

rbe-login:
    @e d rbe login

rbe-status:
    @e d rbe status

doctor:
    @test -x scripts/build
    @command -v e >/dev/null
    @command -v sops >/dev/null
    @test -f config/evm.main-release.json
    @test -f "$HOME/.config/sops/age/keys.txt"
    @if [[ -f secrets/aws.env ]]; then sops decrypt --input-type dotenv --output-type dotenv secrets/aws.env >/dev/null; else echo 'missing encrypted secrets/aws.env' >&2; exit 1; fi
    @e d rbe status

paths:
    @printf 'workspace: %s\n' "${ELECTRON_WORKSPACE:-${XDG_CACHE_HOME:-$HOME/.cache}/electron-build}"
    @printf 'depot tools: %s\n' "${DEPOT_TOOLS_DIR:-${ELECTRON_WORKSPACE:-${XDG_CACHE_HOME:-$HOME/.cache}/electron-build}/depot_tools}"
    @printf 'git cache: %s\n' "${GIT_CACHE_PATH:-${ELECTRON_WORKSPACE:-${XDG_CACHE_HOME:-$HOME/.cache}/electron-build}/git-cache}"
    @printf 'sccache: %s\n' "${SCCACHE_DIR:-${ELECTRON_WORKSPACE:-${XDG_CACHE_HOME:-$HOME/.cache}/electron-build}/sccache}"
