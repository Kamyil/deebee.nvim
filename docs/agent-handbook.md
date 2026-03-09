# Agent Handbook

This document exists so other coding agents and contributors can follow the project's current decisions without re-deriving them.

## 1. Current Truths

Do not casually revisit these decisions.

- Minimum Neovim version is `0.11+`
- Frontend is `Lua`
- Backend worker is `Rust`
- The worker is an external process over stdio RPC
- First ship target is `PostgreSQL`
- Next target is `Oracle`
- Oracle support may require `Oracle Instant Client`
- Editable grids are limited to safe `single-table` result sets in v1
- Worker binaries come from the same repo's GitHub Releases
- Worker binaries auto-download on first use
- Plugin accepts only the exact pinned worker version
- Worker updates happen only on explicit command

## 2. Product Philosophy

The plugin is not trying to become a full DataGrip clone before release.

The real product target is:

- excellent Postgres workflow inside Neovim
- strong inspection and query UX
- safe editable table workflows
- architecture that cleanly expands to Oracle

If a proposed change improves breadth while hurting write safety, compatibility, or Postgres quality, reject it.

## 3. Most Important Constraints

### 3.1 Write Safety First

- never broaden writable query support casually
- v1 writable results must be clearly provable
- if the worker cannot prove writability, the UI must stay read-only

### 3.2 Compatibility First

- exact worker version match is required
- protocol mismatch is fatal
- do not build features that assume loose plugin/worker compatibility

### 3.3 Paging First

- do not render full large result sets into buffers eagerly
- design data flow around pages and viewport state

## 4. Ownership Rules

Lua owns:

- commands
- windows and buffers
- explorer rendering
- notes UX
- result-grid interaction state
- installer and health UI

Rust owns:

- DB connections
- query execution
- metadata introspection
- write-safety checks
- edit sessions
- DML synthesis

If a piece of logic depends on database semantics, it usually belongs in Rust.

## 5. Editable Grid Rules

Writable only when all are true:

- one base table
- writable columns known
- row identity known
- projection is safe

Read-only by default for:

- joins
- aggregates
- grouped queries
- ambiguous views
- complex CTEs

Identity strategy:

- Postgres: PK/unique key first, `ctid` fallback only for active sessions
- Oracle: PK/unique key first, `ROWID` fallback

## 6. Release and Install Rules

- same repository for plugin and worker assets
- target-triple asset naming
- archives plus checksums
- exact version install path under `stdpath("data")`
- no silent auto-update

## 7. What To Read Before Implementing

Start with these files in order:

1. `docs/implementation-spec.md`
2. `docs/architecture.md`
3. `docs/rpc-protocol.md`
4. `docs/editable-grid-spec.md`
5. `docs/release-distribution.md`
6. `docs/roadmap.md`

## 8. Good Defaults For Early Contributors

- choose simpler architecture over cleverness
- prefer explicit protocol payloads
- keep adapter-specific code out of Lua
- keep write behavior conservative
- expose health/debug info early
- optimize for maintainability and safety before polish

## 9. Smell List

If you are about to do any of these, stop and reconsider:

- store core row identity only in rendered buffer text
- make Lua decide complex DB writability
- assume Oracle should match Postgres metadata one-to-one
- widen writable support to joins for convenience
- auto-update worker binaries behind the user's back
- weaken exact-version worker checks

## 10. How To Make Decisions

When a new implementation choice appears, prefer the option that best preserves:

1. correctness and safe writes
2. pinned plugin/worker compatibility
3. strong Postgres workflow
4. architecture reuse for Oracle
5. UI polish
