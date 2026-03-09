# Editable Grid Specification

This document defines the editable result-grid model.

Editable grids are one of the hardest features in the project, so the rules here are intentionally conservative.

## 1. Product Position

The grid is not a spreadsheet clone and should not be designed as one.

It is a paged, navigable data view that supports safe editing for supported query shapes.

The product target is:

- great editing of ordinary table rows
- explicit transaction control
- clear dirty-state feedback
- predictable behavior under paging

Not the target:

- arbitrary writable SQL
- broad query inference magic
- fully spreadsheet-like fill/range semantics in v1

## 2. V1 Scope

V1 editable support exists only when the worker can prove all of the following:

- exactly one base table backs the result set
- writable columns are known
- row identity is known
- projection can be mapped back safely
- query shape is supported by the adapter's write synthesizer

Examples that should usually be writable:

- `select * from users`
- `select id, email, status from users`
- `select id, email from users where active = true order by id`

Examples that should be read-only:

- joins
- aggregates
- grouped queries
- unions
- ambiguous views
- derived columns without safe reverse mapping

## 3. Row Identity Rules

The grid must always know how a displayed row maps back to a database row.

Preferred strategies:

1. primary key
2. unique key
3. engine-specific locator fallback only for active session scope

### 3.1 PostgreSQL

- prefer PK or unique key
- may fall back to `ctid` only for active edit sessions
- `ctid` is not persistent identity and must not be stored as durable row identity

### 3.2 Oracle

- prefer PK or unique key
- may fall back to `ROWID`

## 4. Edit Session Model

An editable grid is backed by a worker-managed edit session.

### 4.1 Session Start

When a user requests edit mode:

1. Lua asks the worker whether the current result is writable.
2. Worker returns write capability metadata.
3. If writable, Lua opens or switches into edit-session mode.
4. Session keeps track of transaction context, row identity strategy, and writable columns.

### 4.2 Session State

Lua maintains interaction state:

- visible page
- focused row and column
- dirty cells
- inserted rows
- deleted rows
- validation errors
- local edit buffers

Worker maintains backend state:

- transaction boundary
- write rules
- row identity mapping
- current canonical row values

## 5. Grid Rendering Model

The rendered buffer is a view, not the source of truth.

Recommended design:

- maintain an in-memory grid model in Lua
- render visible rows into a scratch buffer
- decorate state with highlights and extmarks
- re-render only affected rows or windows when possible

Do not use raw buffer text as the only store for:

- row identity
- dirty tracking
- inserted/deleted flags
- validation error association

## 6. Editing Modes

### 6.1 Inline Edit

Used for short, simple scalar values.

Expected targets:

- text
- numeric values
- booleans
- small dates/timestamps

### 6.2 Floating Cell Editor

Used for larger or awkward values.

Expected targets:

- long text
- JSON
- large string columns
- potentially CLOB-like values in later adapters

This is especially important because cell content can be wider than the viewport and uncomfortable to edit directly inside a grid row.

## 7. Dirty-State Feedback

Users must always know what changed.

Required signals:

- dirty-cell highlight
- dirty-row indicator
- inserted-row indicator
- deleted-row indicator
- session-level dirty summary

Optional later improvements:

- column-specific validation badges
- tooltip-like error surfaces

## 8. Row Actions

The grid should support at least these row-level actions in v1:

- edit cell
- insert row
- duplicate row (optional if cheap)
- delete row
- refresh row
- revert row

Session-level actions:

- commit
- rollback
- refresh page

## 9. Change Application Model

Changes are staged first and committed explicitly.

### 9.1 Staging

Local edits are accumulated as a changeset keyed by row identity and column.

Change types:

- insert
- update
- delete

### 9.2 Apply / Commit

Depending on implementation, the worker may either:

- apply changes incrementally within an open transaction, then commit later
- or accept the whole changeset on commit

Preferred model:

- open transaction-backed edit session
- apply row operations as needed
- let user commit or rollback at session level

This makes refresh and error recovery more straightforward.

## 10. Validation

Validation exists at multiple levels.

### 10.1 Client-Side Validation

Lua may do cheap UX-level checks:

- empty required field when clearly known
- malformed local edit representation

### 10.2 Worker-Side Validation

Worker is the authority for:

- column writability
- type conversion rules
- key/identity availability
- SQL generation validity
- adapter-specific constraints

### 10.3 Database Validation

Final authority remains the database.

Constraint or trigger failures must come back with enough context for Lua to mark affected rows or cells.

## 11. Refresh Behavior

The grid must support refresh without destroying the user model.

Refresh types:

- row refresh
- page refresh
- full query rerun

Rules:

- do not silently discard local staged changes
- when refresh would invalidate local edits, require explicit user choice or block the action
- if row identity changes after update, worker must return the new identity mapping

## 12. Read-Only Explanation UX

When a grid is not writable, the plugin should not just disable editing silently.

It should surface a reason such as:

- query uses a join
- result has no stable row identity
- projection includes derived expressions that cannot be written back safely
- adapter does not support writable sessions for this result shape

This is important both for UX and for debugging.

## 13. Postgres-Specific Notes

- `ctid` can be used as a practical active-session fallback
- updates can change `ctid`, so the worker must refresh row identity after writes when needed
- PK/unique-key routes are still preferred and should be used whenever available

## 14. Oracle-Specific Notes

- `ROWID` is a practical fallback locator for active edit sessions
- Oracle metadata and privilege constraints can make writability more variable than Postgres
- Oracle support should reuse the same session model and only specialize adapter behavior

## 15. Hard Constraints

Never do any of the following in v1:

- infer writable joins casually
- update arbitrary views without explicit proven support
- auto-commit edits behind the user's back
- hide write errors inside a generic refresh

## 16. Acceptance Criteria

Editable grid work is acceptable for v1 when:

- supported single-table result sets enter edit mode predictably
- unsupported result sets clearly remain read-only
- dirty state is obvious
- commit and rollback are explicit and dependable
- changed rows can be refreshed without corrupting session state
- failure cases return actionable messages
