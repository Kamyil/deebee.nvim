# Implementation Specification

This document is the primary source of truth for `deebee.nvim`.

It captures the product scope, architecture, release model, and implementation decisions gathered so far. Other design docs should refine this document, not contradict it.

## 1. Product Summary

`deebee.nvim` is a Neovim database plugin that aims to provide a serious database workflow inside Neovim with a UX inspired by JetBrains database tools, while still respecting Neovim's strengths and constraints.

The plugin targets:

- schema browsing and object inspection
- SQL scratchpads and query execution
- large result-set viewing with paging
- editable result grids for the safe and common case
- notes and query history
- optional mouse support and context menus

The implementation model is:

- `Lua` for UI and editor integration
- `Rust` for the external worker process
- `PostgreSQL` as the first-class launch database
- `Oracle` as the immediate next adapter

## 2. Locked Decisions

The following decisions are intentionally locked unless there is a strong technical reason to revisit them.

### 2.1 Editor Baseline

- Minimum supported Neovim version is `0.11+`
- Lower versions are out of scope

Reasoning:

- reduces compatibility overhead
- gives a cleaner modern API baseline
- improves confidence around floating windows, extmarks, redraw behavior, and plugin ergonomics

### 2.2 Frontend and Backend Split

- Frontend is written in `Lua`
- Database work happens in a separate `Rust` worker process
- Lua does not directly embed database drivers

Reasoning:

- UI and editor integration belong in Lua
- async execution, paging, metadata processing, and long-lived connections fit better in an external worker
- Rust provides a good runtime for long-lived, low-overhead backend logic

### 2.3 Launch Database Scope

- Release 1 is `PostgreSQL-first`
- Oracle is the next release after PostgreSQL, not part of the initial ship gate
- Oracle support is allowed to require `Oracle Instant Client`

### 2.4 Editable Grid Scope

- Editable grids are allowed in v1 only for safe `single-table` result sets
- Complex query-shape inference is out of scope for v1
- Joins, grouped queries, aggregates, ambiguous views, and most complex CTEs are read-only

### 2.5 Worker Distribution

- Worker binaries are built and released from the same repository
- Prebuilt binaries are the primary distribution method
- The plugin auto-downloads the worker on first use when needed
- The plugin expects one exact worker version
- Updates happen only on explicit command

### 2.6 Supported Install UX

- On-demand auto-download is allowed
- Silent background auto-updates are not allowed
- Manual override path for a local worker binary must exist for development and debugging

## 3. Product Goals

### 3.1 Main Goals

- Make database use inside Neovim feel intentional, fast, and dependable
- Make Postgres support excellent before broadening scope
- Provide a strong object-inspection workflow
- Provide a great query runner with cancellation, paging, and history
- Support safe editable grids for common table-oriented workflows
- Build an architecture that can absorb Oracle without UI rework

### 3.2 Non-Goals For V1

- full DataGrip parity
- arbitrary writable query inference
- diagram generation
- schema diff and refactor tooling
- full spreadsheet-style range editing
- deep PL/SQL debugging
- advanced migration management

## 4. UX Vision

The plugin should feel like a serious workspace, not a pile of commands.

Core surfaces:

- connection explorer
- object inspection view
- SQL editor / scratch buffer
- results grid
- notes buffer
- status / progress / error surfaces

UX principles:

- keyboard-first
- mouse-supported, not mouse-dependent
- explicit write operations
- smooth behavior on large result sets
- predictable layout and command model

## 5. High-Level Architecture

The system has two major runtime pieces.

### 5.1 Lua Frontend

Responsibilities:

- user commands
- keymaps
- layout and windows
- floating UI and context menus
- tree/explorer rendering
- result-grid rendering and interaction state
- edit buffer state for cells and rows
- worker discovery, install, launch, restart
- health checks
- local config interpretation

The Lua frontend should not:

- talk directly to databases
- implement SQL driver logic
- own cross-session DB metadata caches beyond light UI cache wrappers

### 5.2 Rust Worker

Responsibilities:

- database connections and pools
- query execution
- streaming / paging
- metadata introspection
- SQL object inspection and DDL fetches
- transaction-scoped edit sessions
- DML generation for editable grids
- adapter abstraction across Postgres and Oracle
- version / protocol handshake

The Rust worker should not:

- own Neovim window logic
- make layout decisions
- implement editor interaction semantics

## 6. Repository Layout

Planned structure:

```text
.
|- plugin/
|  `- deebee.lua
|- lua/
|  `- deebee/
|     |- init.lua
|     |- commands.lua
|     |- config.lua
|     |- health.lua
|     |- installer.lua
|     |- rpc.lua
|     |- state/
|     |- ui/
|     |- explorer/
|     |- query/
|     |- grid/
|     `- notes/
|- crates/
|  `- deebee-worker/
|     |- Cargo.toml
|     `- src/
|- docs/
`- .github/
   `- workflows/
```

Guidance:

- keep UI code separate from worker/process code
- keep database-adapter code inside the worker
- keep protocol definitions centralized
- isolate installer logic so it can be tested independently of query features

## 7. Database Support Strategy

### 7.1 PostgreSQL First

Postgres is the initial adapter because it is the main real target and has a clean Rust ecosystem.

Initial capabilities:

- connect via saved profiles
- list schemas, tables, views, functions, sequences, indexes, and constraints
- inspect columns and DDL
- execute SQL
- cancel queries
- page through result sets
- derive writable single-table edit sessions

Expected Rust stack:

- `tokio`
- `tokio-postgres`
- worker-side abstractions for metadata and query results

### 7.2 Oracle Immediately After

Oracle is the second adapter and should reuse the same UI and most of the same worker abstractions.

Initial Oracle assumptions:

- use `rust-oracle` first
- allow Oracle Instant Client requirement
- treat Oracle setup as optional runtime capability
- expose health-check feedback when Oracle is requested but unavailable

Oracle caveats to design for:

- different metadata shape
- more setup friction
- wider privilege variance
- more complex object categories and source inspection cases
- runtime dependency on client libraries when using the initial adapter

## 8. Query Execution Model

The query runner is one of the main product surfaces.

### 8.1 Core Behaviors

- run current statement
- run selected SQL
- run current buffer
- cancel in-flight query
- show progress and status
- store query history
- preserve enough context to reopen or rerun a previous query

### 8.2 Query Lifecycle

1. User invokes a query action from Lua.
2. Lua identifies the execution target and active connection.
3. Lua sends a `run_query` request to the worker.
4. Worker validates connection, starts execution, and returns a query handle.
5. Worker streams metadata and result-page information back.
6. Lua opens or updates the results view.
7. Additional pages are fetched on demand.
8. User may cancel, export, inspect, or open an editable session when allowed.

### 8.3 Paging Rules

- the UI must not render entire large result sets eagerly
- the worker must own server-side or worker-side pagination state
- the UI requests pages by offset/cursor token, not by reissuing the raw query blindly
- fetch size should be configurable later, but the first version can use a stable default

### 8.4 Cancellation

- cancellation must be first-class in the protocol
- Postgres should use real query cancellation support
- Oracle cancellation support can be phased in if required by driver limitations

## 9. Result Grid Design

The results grid is not a spreadsheet clone.

It is a navigable, paged, table-like editor surface built on normal Neovim buffers plus local state.

### 9.1 Grid Principles

- grid must work well with keyboard navigation
- grid must remain stable under paging
- grid must not depend on rendering tens of thousands of rows at once
- edits must be explicit and visible
- dirty state must be obvious

### 9.2 Display Strategy

- use a real scratch buffer for row display
- keep header and row rendering deterministic
- maintain a local row model separate from the buffer text
- use highlights and extmarks for state decoration, not as the main data store

### 9.3 Editing Modes

- inline editing for simple scalar values
- floating editor for large text, JSON, and long fields
- staged row insert/delete actions
- explicit commit and rollback actions at the edit-session level

See `docs/editable-grid-spec.md` for the detailed model.

## 10. Safe Write Model

The plugin must be conservative about data writes.

### 10.1 V1 Writable Criteria

A result set is writable only if the worker can prove all of the following:

- it maps to one base table
- writable columns are known
- a stable row identity is available
- the projection is not ambiguous
- the query shape is supported by the write synthesizer

### 10.2 V1 Read-Only Cases

- joins
- aggregates
- grouped queries
- ambiguous views
- unions
- most complex CTEs
- result sets without sufficient row identity

### 10.3 Identity Strategy

Preferred order:

- primary key
- unique key
- engine-specific physical locator fallback only for active edit sessions

Postgres fallback:

- `ctid`
- only valid as a short-lived active-session fallback
- must not be treated as stable long-term identity

Oracle fallback:

- `ROWID`
- acceptable as a practical fallback for an active edit session

## 11. Notes and Scratchpads

Notes are part of the product, not an afterthought.

V1 notes expectations:

- per-connection notes
- per-object notes
- free-form SQL scratch buffers
- easy jump between explorer selection and note context

Storage format can be local filesystem data managed by the Lua side unless a stronger worker-owned model becomes necessary.

## 12. Explorer and Inspection UX

Explorer requirements:

- show saved connections
- show schemas and object groups
- expand tables, views, functions, packages, etc. based on adapter support
- support search/filter later, but leave room for it from the start

Inspection requirements:

- columns and types
- indexes
- constraints
- estimated row counts where available
- DDL/source preview
- refresh action

Mouse support can be layered on top of a keyboard-first command model.

## 13. Mouse and Context Menu Support

Mouse support is a product requirement, but not the main interaction model.

V1 posture:

- support click navigation where practical
- support right-click context menus as optional UX sugar
- do not make core flows depend on terminal mouse reliability

Context menu targets:

- explorer nodes
- grid rows/cells
- query buffer selections

Examples of menu actions:

- inspect
- open DDL
- refresh
- run query
- edit row
- delete row
- commit / rollback

## 14. Worker Protocol Requirements

Protocol properties:

- request/response over stdio
- explicit event stream for progress and status
- strict version handshake
- typed error categories
- no silent protocol degradation

The protocol must support:

- install-time validation
- startup handshake
- connection lifecycle
- query lifecycle
- result paging
- edit sessions
- metadata inspection
- health and capability reporting

See `docs/rpc-protocol.md` for details.

## 15. Worker Versioning and Compatibility

The plugin and worker move together by exact pinned version.

Rules:

- every plugin release pins one worker version
- plugin accepts only that worker version and protocol version
- if local worker mismatches, plugin prompts reinstall/update flow
- worker upgrades occur only through explicit command or plugin upgrade path

This avoids subtle compatibility breakage and makes issues easier to diagnose.

## 16. Distribution and Installer Behavior

Release model:

- worker assets ship from this repository's GitHub Releases
- same release tag as the plugin version
- target-specific archives plus checksums and a manifest

Installer behavior:

- install exact pinned version on first use if missing
- download only on-demand
- verify checksums before activation
- store versioned worker installs under Neovim data dir
- support local override path for development

See `docs/release-distribution.md` for detailed installer and release behavior.

## 17. Configuration Model

Configuration should separate product-level config from secrets.

V1 config categories:

- UI preferences
- worker path override
- download behavior preferences
- connection definitions or connection references
- optional notes storage configuration later

Credentials should not be stored casually in plain text without at least acknowledging the tradeoff.

Practical v1 position:

- allow user-supplied connection strings or structured configs
- provide room for environment variable expansion
- avoid inventing secret-management complexity too early

## 18. Logging and Diagnostics

The system needs explicit diagnostics from day one.

### 18.1 Lua Side

- install logs
- worker startup logs
- RPC error summaries
- user-facing health report

### 18.2 Worker Side

- startup logs
- adapter capability logs
- query lifecycle logs
- install/runtime environment issues

### 18.3 Health Check

`CheckHealth` should report at least:

- Neovim version compatibility
- worker presence and version
- worker protocol match
- active platform target
- release/asset resolution issues
- Oracle client status when Oracle support is requested or installed

## 19. Testing Strategy

Testing must begin at the architecture level, not only after the UI exists.

### 19.1 Rust Tests

- protocol serialization and deserialization
- metadata normalization
- query-result shape handling
- writable-query detection
- DML synthesis
- adapter-specific integration tests

### 19.2 Lua / Neovim Tests

- installer behavior
- worker resolution and version mismatch handling
- basic command flow
- explorer state transitions
- paging behavior
- grid navigation and edit-session behavior

### 19.3 Integration Fixtures

Need test fixtures for:

- simple PK-backed table
- unique-key table
- table without explicit key
- generated columns
- nullable columns
- JSON / JSONB
- large text fields
- unsafe query shapes that must remain read-only

## 20. Security and Safety Rules

- never perform writes without an explicit user action
- never silently transform a read-only result into a writable result
- do not persist credentials in surprising locations
- verify downloaded worker assets before execution
- fail closed on version mismatch
- keep write scope conservative in v1

## 21. Milestones

### Milestone 0 - Platform Foundation

- repository skeleton
- Lua bootstrap
- Rust worker skeleton
- protocol handshake
- installer and health check
- release pipeline for worker binaries

### Milestone 1 - Postgres Core

- connection profiles
- run query
- cancel query
- paging
- results view
- query history

### Milestone 2 - Inspection Workspace

- explorer tree
- object inspection
- DDL/source view
- search groundwork
- notes and scratchpads

### Milestone 3 - Postgres Editable Grid

- read-only grid first
- writable-query detection
- edit session lifecycle
- commit and rollback
- insert/update/delete/refresh/revert

### Milestone 4 - Postgres Polish

- explain plan
- export
- mouse/context menu pass
- improved error and loading UX

### Milestone 5 - Oracle

- Oracle adapter
- Oracle health checks
- Oracle inspection support
- Oracle edit-session support using the same UI model

## 22. Acceptance Criteria For First Release

Postgres first release is ready when all of the following are true:

- worker auto-installs cleanly on supported platforms
- plugin can connect to Postgres using configured profiles
- user can run and cancel queries
- user can browse schemas and inspect objects
- result sets page smoothly without trying to render everything at once
- editable grids work for safe single-table result sets
- unsafe result shapes stay read-only with a clear explanation
- history and notes are usable
- health checks explain installation and compatibility failures clearly

## 23. Known Open Questions

These are not blockers for the initial architecture, but they will need decisions later.

- exact config-file shape for saved connections
- how notes are stored and keyed on disk
- how much query history should be retained by default
- whether future worker release tags always equal plugin tags or gain a subversion model
- whether Oracle support later moves from `rust-oracle` to a more mature pure-Rust alternative if one emerges

## 24. Contributor Rule

When in doubt, contributors and coding agents should preserve these priorities in order:

1. correctness and safety of writes
2. predictable plugin/worker compatibility
3. smooth Postgres workflow
4. architecture reuse for Oracle
5. UI polish and feature breadth
