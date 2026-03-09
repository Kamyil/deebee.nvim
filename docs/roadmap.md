# Roadmap

This document translates the implementation spec into milestones and deliverables.

## 1. Release Strategy

Release order is fixed:

1. PostgreSQL-first release
2. Oracle support immediately after

The PostgreSQL release is not blocked on Oracle.

## 2. Milestone 0 - Foundation

Goal: create the technical platform the rest of the plugin depends on.

Deliverables:

- basic repository layout
- Lua bootstrap and command registration
- Rust worker crate
- stdio RPC transport
- handshake and protocol versioning
- worker installer
- worker health checks
- release workflow for worker binaries

Exit criteria:

- plugin can install and start exact pinned worker on supported platforms
- plugin can report worker version and protocol status

## 3. Milestone 1 - Postgres Query Core

Goal: make the plugin useful for query execution.

Deliverables:

- Postgres connection support
- run current statement
- run selection
- cancel query
- paged results
- result schema metadata
- basic history recording

Exit criteria:

- user can execute and cancel Postgres queries without freezing the UI
- large result sets page instead of rendering eagerly

## 4. Milestone 2 - Inspection Workspace

Goal: make the plugin useful for browsing and understanding schemas.

Deliverables:

- explorer tree
- schemas and object groups
- table and view inspection
- columns, indexes, constraints
- DDL/source display
- notes and scratchpads

Exit criteria:

- user can browse and inspect Postgres objects comfortably from within Neovim

## 5. Milestone 3 - Editable Grid For Postgres

Goal: support safe row editing for common table workflows.

Deliverables:

- writable-query detection
- read-only explanation UX
- edit-session lifecycle
- dirty state tracking
- insert, update, delete
- refresh and revert
- explicit commit and rollback

Exit criteria:

- supported single-table Postgres results can be edited safely and predictably
- unsupported results remain clearly read-only

## 6. Milestone 4 - Postgres Polish

Goal: improve everyday workflow quality.

Deliverables:

- explain plan
- export support
- mouse actions and context menus
- sticky headers
- better status and error UX

Exit criteria:

- plugin feels coherent and reliable for daily Postgres use

## 7. Milestone 5 - Oracle

Goal: extend the existing architecture to Oracle without reworking the UI model.

Deliverables:

- Oracle adapter
- Oracle runtime health checks
- Oracle explorer support
- Oracle inspection support
- Oracle query execution
- Oracle edit-session support using the same writable-grid constraints

Exit criteria:

- Oracle browsing and querying are viable
- editable single-table result grids work where row identity and writability are provable

## 8. Items Explicitly Deferred

These items should not be allowed to derail the first releases:

- writable join inference
- schema diff/refactor features
- diagram tooling
- broad spreadsheet semantics
- deep stored procedure debugging

## 9. Agent Guidance

When implementation begins, agents should prefer work in this order:

1. protocol and install stability
2. Postgres query runner
3. result paging and rendering stability
4. explorer and inspection UX
5. editable-grid safety
6. polish and secondary UX
7. Oracle adapter
