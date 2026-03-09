# Architecture

This document describes the technical structure of `deebee.nvim` at the system level.

## 1. Runtime Topology

The plugin is split into two runtime layers.

```text
Neovim
  |
  |- Lua frontend
  |    |- commands
  |    |- UI layout
  |    |- explorer
  |    |- query editor integration
  |    |- result grid rendering
  |    |- notes
  |    |- installer / health
  |    `- RPC client
  |
  `- Rust worker (external process over stdio)
       |- handshake / capabilities
       |- adapters
       |    |- postgres
       |    `- oracle
       |- query manager
       |- metadata services
       |- edit-session manager
       `- paging / result state
```

## 2. Frontend Boundaries

Lua owns everything the user directly interacts with.

### 2.1 Lua Responsibilities

- command definitions
- plugin setup
- keymaps
- split and floating window layout
- buffer creation and lifecycle
- explorer rendering
- result-grid rendering
- notes UX
- local interaction state
- worker install, lookup, and process lifecycle
- translating user intent into worker requests

### 2.2 Lua Must Not Own

- DB pools
- DB driver logic
- large metadata normalization code that belongs to adapters
- write-safety inference that depends on DB semantics

## 3. Worker Boundaries

Rust owns the heavy backend logic.

### 3.1 Worker Responsibilities

- parse requests
- version/protocol handshake
- keep connection pools and sessions
- run queries asynchronously or via adapter-appropriate execution model
- stream result metadata and page data
- inspect schemas and objects
- determine result writability
- open and manage edit sessions
- synthesize safe DML
- return normalized data to Lua

### 3.2 Worker Must Not Own

- Neovim window state
- cursor state
- grid layout logic
- note-editing UX

## 4. Adapter Model

The worker should expose a common adapter interface so the frontend stays mostly database-agnostic.

Suggested internal capability areas:

- `connect`
- `disconnect`
- `list_catalog`
- `inspect_object`
- `run_query`
- `cancel_query`
- `open_edit_session`
- `apply_edit_changes`
- `commit`
- `rollback`
- `explain`

Each adapter should normalize metadata into shared worker-facing types before anything is returned to Lua.

## 5. Shared Domain Types

The worker should normalize into stable internal data structures such as:

- connection descriptor
- capability descriptor
- catalog node
- object summary
- object inspection payload
- query handle
- result-set schema
- page payload
- edit-session handle
- row identity descriptor
- write capability descriptor
- structured error

The Lua side should treat these as the contract, not depend on adapter-specific raw payloads.

## 6. Result-Set Data Flow

```text
User action
  -> Lua command handler
  -> RPC request: run_query
  -> Worker validates connection and adapter
  -> Worker starts execution
  -> Worker emits query_started / schema / status events
  -> Worker returns first page or page token
  -> Lua renders grid buffer
  -> User scrolls or navigates
  -> Lua requests more pages
```

Key rule:

- buffer text is a view of worker-backed data, not the authoritative data source

## 7. Edit Session Data Flow

```text
User opens writable result
  -> Lua requests open_edit_session
  -> Worker analyzes result shape and returns write capability
  -> Lua enters grid edit mode
  -> User stages changes locally
  -> Lua sends apply_changes or commit request
  -> Worker generates DML inside transaction
  -> Worker returns updated row state / errors
  -> Lua refreshes row decorations and session status
```

Important rule:

- staged edits live in Lua interaction state until applied
- worker remains source of truth for write validation and DML synthesis

## 8. Buffer and Window Surfaces

Planned core surfaces:

- explorer buffer
- query editor buffer
- results grid buffer
- notes buffer
- optional detail/DDL preview buffer

General guidance:

- prefer stable named scratch buffers over disposable ad-hoc buffers
- keep enough metadata in Lua state tables to reconstruct context after redraws
- avoid encoding critical data solely into rendered text

## 9. State Ownership

### 9.1 Lua State

- active workspace layout
- active connection selection
- open query buffers
- buffer-to-context mappings
- grid viewport state
- staged edit state
- installed worker path and process handle

### 9.2 Worker State

- live connections and pools
- active query handles
- result pagination state
- metadata cache
- active edit sessions
- transaction state

### 9.3 Persistence Candidates

V1 persistence may include:

- connection definitions
- notes
- query history
- installer metadata

Persistent storage details can remain flexible as long as ownership boundaries stay clear.

## 10. Failure Domains

The architecture must tolerate worker failure cleanly.

Examples:

- worker binary missing
- worker checksum mismatch
- worker startup crash
- protocol mismatch
- DB connection failure
- query timeout or cancellation
- adapter unsupported feature

Lua must be able to:

- detect failure
- show a clear status message
- restart worker when sensible
- avoid corrupting local UI state

## 11. Performance Strategy

Performance comes mostly from architecture, not language choice alone.

Main strategies:

- paging instead of full eager rendering
- metadata caching in worker
- narrow redraw scope in Lua
- stable row models separate from rendered text
- explicit viewport refresh rules
- avoid excessive extmark dependence for core data identity

## 12. Oracle Accommodation

Even before Oracle lands, the architecture must leave room for:

- different metadata trees
- different object kinds
- different source-inspection queries
- fallback row locator support (`ROWID`)
- Oracle client availability reporting

This means the frontend must avoid overfitting the explorer or inspection views to Postgres-only assumptions.

## 13. Versioning Contract

There are three distinct compatibility surfaces:

- plugin version
- worker version
- protocol version

Rules:

- plugin pins worker version exactly
- protocol mismatch is fatal
- adapter capability mismatch is surfaced as feature unavailability, not protocol failure

## 14. Health and Install Architecture

Installer and health systems are part of the architecture, not just utilities.

Needed responsibilities:

- detect OS and architecture
- resolve correct release asset
- verify checksums
- unpack to versioned data path
- expose path and version through health report
- report Oracle availability separately from generic worker health

## 15. Architecture Constraint Summary

All future implementation work should preserve these constraints:

- Lua owns UX
- Rust owns DB semantics
- worker is optional until first use, but mandatory for DB actions
- writes are conservative by design
- results are paged
- worker install is exact-versioned and explicit-update
