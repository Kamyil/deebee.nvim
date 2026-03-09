# Decision Log

This file records the key project decisions that are already settled.

Its purpose is simple: when a contributor or coding agent joins the project later, they should not have to reconstruct the design history from chat context.

## Status Legend

- `locked` - do not revisit unless there is a strong technical reason
- `planned` - direction is chosen, implementation details may still evolve
- `open` - intentionally not settled yet

## Locked Decisions

### Platform and Product Shape

- `locked` - Neovim baseline is `0.11+`
- `locked` - product target is a serious Neovim database workflow, not full DataGrip parity before release
- `locked` - workflow should be keyboard-first with mouse/context-menu support layered on top

### Architecture

- `locked` - frontend is `Lua`
- `locked` - backend is a separate `Rust` worker process
- `locked` - Lua talks to the worker over stdio RPC
- `locked` - Lua owns UX, buffers, windows, rendering, installer, and health UI
- `locked` - Rust owns DB semantics, query execution, metadata, edit sessions, and DML generation

### Database Scope

- `locked` - `PostgreSQL` ships first
- `locked` - `Oracle` is added right after the Postgres-first release
- `locked` - Oracle users may be required to have `Oracle Instant Client`
- `planned` - initial Oracle worker implementation should use `rust-oracle`

### Editable Grids

- `locked` - editable grids are a core feature, not a nice-to-have
- `locked` - v1 editable grids are limited to safe `single-table` result sets
- `locked` - joins, aggregates, grouped queries, ambiguous views, and complex CTEs remain read-only in v1
- `locked` - Postgres row identity prefers PK or unique key and may use `ctid` only as active-session fallback
- `locked` - Oracle row identity prefers PK or unique key and may use `ROWID` as fallback
- `locked` - edits are explicit and transaction-scoped with `commit` and `rollback`

### Worker Distribution

- `locked` - worker binaries are shipped from the same repository as the plugin
- `locked` - worker binaries are prebuilt release assets
- `locked` - plugin auto-downloads the worker on first use when missing
- `locked` - plugin uses an exact pinned worker version
- `locked` - worker updates happen only on explicit command
- `locked` - install path should be versioned under `stdpath("data")`
- `planned` - release assets should use target-triple naming plus checksums and manifest files

### Release and Packaging

- `locked` - no silent background worker updates
- `locked` - first-use install is allowed
- `planned` - release assets should be archives (`.tar.gz` on Unix-like systems, `.zip` on Windows)
- `planned` - release matrix should include macOS Intel/Apple Silicon, Linux x86_64/aarch64 GNU, Windows x86_64 MSVC

## Planned Directions

- `planned` - result grid should be a paged scratch-buffer view backed by Lua state, not a spreadsheet clone
- `planned` - notes and scratchpads should be first-class surfaces in the workspace
- `planned` - right-click context menus should exist where practical, but should not be the primary interaction path
- `planned` - `CheckHealth` should cover worker version, protocol match, install path, target triple, and Oracle runtime status

## Intentionally Open Questions

- `open` - exact on-disk config-file format for saved connections
- `open` - exact notes storage format and keying model
- `open` - exact query-history retention policy
- `open` - final wire encoding choice for the RPC layer, as long as framing and protocol guarantees are preserved

## Where To Look Next

For deeper context behind these decisions:

- `docs/implementation-spec.md`
- `docs/architecture.md`
- `docs/rpc-protocol.md`
- `docs/editable-grid-spec.md`
- `docs/release-distribution.md`
- `docs/agent-handbook.md`
