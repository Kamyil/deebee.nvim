# Release and Distribution

This document defines how the Rust worker is packaged, released, installed, and updated.

## 1. Distribution Model

The Rust worker is distributed as prebuilt binaries from the same repository as the plugin.

This is the locked release model.

Consequences:

- one GitHub Releases page
- same version/tag stream as the plugin
- simple asset lookup from Lua
- easy plugin/worker compatibility reasoning

## 2. Versioning Policy

Rules:

- plugin release pins one exact worker version
- worker assets are downloaded for that exact version only
- plugin does not opportunistically use newer compatible workers
- worker updates happen only on explicit command or plugin upgrade flow

Why:

- predictable runtime behavior
- simpler debugging
- cleaner issue reports
- avoids accidental protocol drift

## 3. Supported Release Targets

Target goals:

- `x86_64-apple-darwin`
- `aarch64-apple-darwin`
- `x86_64-unknown-linux-gnu`
- `aarch64-unknown-linux-gnu`
- `x86_64-pc-windows-msvc`

The first implemented release workflow may ship the native-hosted targets first and add Linux `aarch64` after the pipeline is proven stable.

Optional later targets:

- `aarch64-pc-windows-msvc`
- `x86_64-unknown-linux-musl`

## 4. Release Assets

Preferred asset names:

- `deebee-worker-x86_64-apple-darwin.tar.gz`
- `deebee-worker-aarch64-apple-darwin.tar.gz`
- `deebee-worker-x86_64-unknown-linux-gnu.tar.gz`
- `deebee-worker-aarch64-unknown-linux-gnu.tar.gz`
- `deebee-worker-x86_64-pc-windows-msvc.zip`
- `checksums.txt`
- `release-manifest.json`

Why target-triple naming instead of human labels:

- simpler resolution logic
- clearer mapping to build matrix
- easier expansion later

## 5. Archive Format

- macOS and Linux: `.tar.gz`
- Windows: `.zip`

We prefer archives over raw binaries because they:

- behave better across platforms
- let us include metadata later if needed
- make checksum validation cleaner

## 6. Release Manifest

`release-manifest.json` should describe:

- release version
- protocol version
- asset list
- checksums
- supported targets
- optional minimum runtime notes

This gives the Lua installer one normalized source of truth per release.

## 7. Installer Behavior

Installer entry points:

- first use of any DB action
- explicit `:DeebeeInstall`
- explicit `:DeebeeUpdateWorker`

### 7.1 Install Flow

1. Determine expected worker version from plugin code.
2. Detect current target triple.
3. Check local install directory.
4. If exact version already exists and passes handshake, use it.
5. Otherwise download exact release asset and checksums/manifest.
6. Verify checksum.
7. Unpack archive into a versioned install path.
8. Set executable bit if needed.
9. Start worker and perform handshake.
10. Persist install metadata for health/debugging.

### 7.2 Update Policy

- no silent automatic updates
- no background polling for new releases
- update only when user explicitly requests it or installs a newer plugin version that pins a different worker version

## 8. Local Storage Paths

Recommended path shape:

```text
stdpath("data")/deebee/bin/<worker_version>/<target>/deebee-worker
```

Store alongside it:

- manifest copy
- checksum or verification marker
- install metadata file if useful

## 9. Worker Override

There must be a development override.

Examples:

- `vim.g.deebee_worker_path`
- config option pointing to a local executable

Behavior:

- bypass release asset lookup
- still require protocol handshake
- clearly mark override state in health output

## 10. Health Reporting

`CheckHealth` should expose:

- expected worker version
- installed worker version
- protocol version
- target triple
- install path
- whether a local override is active
- whether Oracle runtime prerequisites are available

## 11. Release Workflow Expectations

The release workflow should:

- build each target in CI
- package each worker archive
- generate checksums
- publish assets to GitHub Release for the tag
- include generated release notes where practical

This workflow can closely follow the style already used in the maintainer's other Rust project, while improving it with archives and checksum artifacts.

## 12. Failure Handling

Installer failures must be actionable.

Examples:

- no network available
- target unsupported
- checksum mismatch
- archive unpack failure
- worker handshake mismatch
- file permission issue

The plugin should tell the user what failed and what to do next, such as:

- rerun install command
- update plugin
- use local override
- inspect health output

## 13. Security Rules

- do not execute downloaded binaries without checksum verification
- do not silently replace an existing exact-version install with a different binary
- fail closed on manifest/version mismatch
- prefer exact-version paths over mutable in-place install paths
