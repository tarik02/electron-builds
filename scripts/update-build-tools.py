#!/usr/bin/env python3

import json
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


def command(*args: str, cwd: Path | None = None, capture: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        check=True,
        text=True,
        capture_output=capture,
    )


def resolve_commit(ref: str) -> str:
    if re.fullmatch(r"[0-9a-f]{40}", ref):
        return ref

    for arguments in (
        ("--refs", f"refs/heads/{ref}"),
        (f"refs/tags/{ref}^{{}}",),
        ("--refs", f"refs/tags/{ref}"),
    ):
        output = command(
            "git",
            "ls-remote",
            "--quiet",
            "https://github.com/electron/build-tools.git",
            *arguments,
            capture=True,
        ).stdout
        if output:
            commit = output.split()[0]
            if re.fullmatch(r"[0-9a-f]{40}", commit):
                return commit

    raise RuntimeError(f"could not resolve build-tools ref: {ref}")


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <branch-or-commit>", file=sys.stderr)
        return 2

    repo_root = Path(__file__).resolve().parents[1]
    flake = repo_root / "flake.nix"
    missing_hashes = repo_root / "config/build-tools-missing-hashes.json"
    original_flake = flake.read_text()
    original_missing_hashes = missing_hashes.read_text()

    try:
        commit = resolve_commit(sys.argv[1])
        archive = f"https://github.com/electron/build-tools/archive/{commit}.tar.gz"
        source_metadata = json.loads(
            command(
                "nix",
                "store",
                "prefetch-file",
                "--json",
                "--unpack",
                "--name",
                "electron-build-tools.tar.gz",
                archive,
                capture=True,
            ).stdout
        )

        with tempfile.TemporaryDirectory(prefix="electron-build-tools-") as temporary:
            temporary_root = Path(temporary)
            source = temporary_root / "source"
            shutil.copytree(source_metadata["storePath"], source)
            for path in source.rglob("*"):
                if not path.is_symlink():
                    path.chmod(path.stat().st_mode | stat.S_IWUSR)

            lockfile = source / "yarn.lock"
            lockfile_text = lockfile.read_text()
            lockfile_match = re.search(r"^__metadata:\n  version: (\d+)\n", lockfile_text, re.MULTILINE)
            if lockfile_match is None or lockfile_match.group(1) != "8":
                version = lockfile_match.group(1) if lockfile_match else "missing"
                raise RuntimeError(
                    f"unexpected Yarn lockfile version: {version}; "
                    "update buildToolsLockfilePatch in flake.nix first"
                )
            lockfile.write_text(lockfile_text.replace("  version: 8\n", "  version: 9\n", 1))

            fetcher = command(
                "nix",
                "eval",
                "--impure",
                "--raw",
                "--expr",
                f'let flake = builtins.getFlake "{repo_root}"; pkgs = import flake.inputs.nixpkgs {{}}; in pkgs.yarn-berry_4.yarn-berry-fetcher',
                capture=True,
            ).stdout.strip()
            fetcher_binary = f"{fetcher}/bin/yarn-berry-fetcher"

            missing_output = command(
                fetcher_binary,
                "missing-hashes",
                str(lockfile),
                capture=True,
            ).stdout
            json.loads(missing_output)
            missing_hashes_temp = temporary_root / "missing-hashes.json"
            missing_hashes_temp.write_text(missing_output)

            cache_dir = temporary_root / "cache"
            cache_dir.mkdir()
            cache_hash = command(
                fetcher_binary,
                "prefetch",
                str(lockfile),
                str(missing_hashes_temp),
                cwd=cache_dir,
                capture=True,
            ).stdout.strip()
            if not re.fullmatch(r"sha256-[A-Za-z0-9+/=]+", cache_hash):
                raise RuntimeError(f"could not read Yarn cache hash: {cache_hash!r}")

            updated_flake = original_flake
            updated_flake, count = re.subn(
                r'(repo = "build-tools";\n\s+rev = ")[^"]+(\")',
                rf"\g<1>{commit}\g<2>",
                updated_flake,
                count=1,
            )
            if count != 1:
                raise RuntimeError("could not update build-tools revision in flake.nix")
            updated_flake, count = re.subn(
                r'(rev = "[^"]+";\n\s+hash = ")[^"]+(\")',
                rf"\g<1>{source_metadata['hash']}\g<2>",
                updated_flake,
                count=1,
            )
            if count != 1:
                raise RuntimeError("could not update build-tools source hash in flake.nix")
            updated_flake, count = re.subn(
                r'(build_tools_revision=")[^"]+(\")',
                rf"\g<1>{commit}\g<2>",
                updated_flake,
                count=1,
            )
            if count != 1:
                raise RuntimeError("could not update workspace revision in flake.nix")
            updated_flake, count = re.subn(
                r'(offlineCache = .*?\n\s+inherit \(finalAttrs\) src missingHashes patches;\n\s+hash = ")[^"]+(\")',
                rf"\g<1>{cache_hash}\g<2>",
                updated_flake,
                count=1,
                flags=re.DOTALL,
            )
            if count != 1:
                raise RuntimeError("could not update Yarn cache hash in flake.nix")

            missing_hashes.write_text(missing_output)
            flake.write_text(updated_flake)

        command("nix", "build", ".#default", "--no-link", "--impure", cwd=repo_root)
    except Exception as error:
        flake.write_text(original_flake)
        missing_hashes.write_text(original_missing_hashes)
        print(f"build-tools update failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        return 1

    print(f"updated build-tools to {commit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
