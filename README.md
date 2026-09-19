# Electron builds

This repository contains the Electron version matrix, local patches, build-tools configuration, and upload recipe. The large Electron and Chromium trees stay in a persistent workspace outside the repository.

Run the checkout directly on the build host. The repository does not need to copy source or artifacts through a second machine.

Enter the build environment with:

```sh
nix develop
```

The task interface is provided by `just`:

```sh
just paths
just doctor
just build 43
```

The shell keeps source and caches under `$ELECTRON_WORKSPACE`, defaulting to `~/.cache/electron-build`. Set it to a durable disk on the build host, for example:

```sh
export ELECTRON_WORKSPACE=/var/lib/buildhost/electron-builds/electron
nix develop
```

Existing depot tools and git cache directories can be reused by setting `DEPOT_TOOLS_DIR`, `GIT_CACHE_PATH`, and `SCCACHE_DIR` before entering the shell.

The shell copies the pinned Electron build-tools checkout into the workspace when its revision is missing or changed. The checkout is built by Nix with an offline Yarn dependency cache, so entering the shell does not run a package manager. It also creates the build-tools configuration from the checked-in template. `e sync` then clones or updates the large source tree in that workspace. Later builds reuse it.

Yarn is used here because Electron's build-tools repository pins Yarn Berry, its lockfile, and its Yarn runtime. Replacing it with npm or pnpm would mean maintaining a different dependency lock and install path.

Refresh that pinned checkout with an explicit upstream ref. The task regenerates the optional-package hashes and Yarn cache hash, then verifies the environment:

```sh
just update-build-tools main
```

AWS credentials belong in an encrypted `secrets/aws.env` file. Copy the example, edit the plaintext copy, then encrypt it and remove the plaintext file:

```sh
cp secrets/aws.env.example /tmp/electron-aws.env
$EDITOR /tmp/electron-aws.env
sops encrypt --input-type dotenv --output-type dotenv \
  /tmp/electron-aws.env > secrets/aws.env
rm /tmp/electron-aws.env
```

Commit the encrypted file. Keep the private age key on the build host. The build script decrypts the file in memory and never writes a plaintext copy.

NotGoma credentials are short-lived and stay on the build host. Run `just rbe-login` when the credential expires. The release config enables Siso remote execution; use `just build-local 43` when deliberately building locally.
