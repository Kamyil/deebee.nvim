# RPC Protocol Specification

This document defines the high-level protocol between the Lua frontend and the Rust worker.

The goal is not to finalize wire encoding details yet, but to lock the request model, event model, and compatibility rules.

## 1. Transport

- transport: stdio
- request/response model: message-based RPC
- recommended encoding: MessagePack or length-prefixed JSON
- requirement: deterministic framing and robust error handling

The exact encoding is an implementation detail as long as the request model remains stable and testable.

## 2. Compatibility Rules

The protocol must be explicit about compatibility.

At worker startup, Lua must perform a handshake before issuing feature requests.

Handshake must validate:

- plugin version
- expected worker version
- protocol version
- worker-reported version
- adapter capabilities

Protocol mismatch is fatal.

Worker version mismatch is fatal.

Missing adapter capability is not fatal unless the user tries to use that adapter.

## 3. Message Categories

Messages are divided into three categories.

### 3.1 Requests

Sent from Lua to worker.

Each request must include:

- request id
- method name
- params object

### 3.2 Responses

Sent from worker to Lua as direct answers to requests.

Each response must include:

- request id
- success payload or structured error

### 3.3 Events

Sent from worker to Lua asynchronously.

Used for:

- query progress
- query completion
- query failure after start
- logs or status notifications where appropriate

## 4. Structured Error Model

Errors must be machine-readable.

Suggested fields:

- `code`
- `category`
- `message`
- `details`
- `retryable`
- `user_action`

Suggested categories:

- `protocol`
- `install`
- `worker_startup`
- `connection`
- `authentication`
- `permission`
- `query`
- `cancellation`
- `writability`
- `validation`
- `unsupported`
- `internal`

## 5. Core Methods

The initial protocol should support the following methods.

### 5.1 Handshake and Health

#### `handshake`

Request fields:

- `plugin_version`
- `expected_worker_version`
- `protocol_version`

Response fields:

- `worker_version`
- `protocol_version`
- `capabilities`
- `adapters`
- `platform`

#### `health`

Used to expose worker environment and adapter availability.

Response fields may include:

- generic worker health
- adapter availability
- Oracle runtime availability status
- install path

### 5.2 Connection Lifecycle

#### `list_connections`

Returns known configured connections or worker-resolved connection summaries.

#### `connect`

Request fields:

- `connection_id` or resolved connection descriptor

Response fields:

- `session_id`
- `adapter`
- `server_version`
- `capabilities`

#### `disconnect`

Request fields:

- `session_id`

#### `ping_connection`

Used for health and reconnection checks.

### 5.3 Catalog and Inspection

#### `list_catalog`

Lists top-level or nested explorer nodes.

Request fields:

- `session_id`
- `node_kind`
- `node_path`

#### `inspect_object`

Returns normalized inspection payload for one object.

Request fields:

- `session_id`
- `object_ref`

Response fields may include:

- summary metadata
- columns
- indexes
- constraints
- row count estimate
- DDL/source text

### 5.4 Query Lifecycle

#### `run_query`

Request fields:

- `session_id`
- `sql`
- `execution_context`
- `page_size`

Response fields:

- `query_id`
- initial status

Events:

- `query_started`
- `query_schema`
- `query_page_ready`
- `query_completed`
- `query_failed`

#### `fetch_page`

Request fields:

- `query_id`
- `page_token` or page index

Response fields:

- rows
- page metadata
- end-of-results signal

#### `cancel_query`

Request fields:

- `query_id`

Response fields:

- accepted / not running / failed

### 5.5 History and Explain

#### `explain_query`

Query plan support, starting with Postgres.

#### `export_result`

Optional v1.1-style method if export is worker-managed.

### 5.6 Editable Grid

#### `open_edit_session`

Opens a writable session from a supported result shape.

Request fields:

- `query_id` or result reference
- `page_state`

Response fields:

- `edit_session_id`
- `writable`
- `write_reason` or `read_only_reason`
- `row_identity_strategy`
- `writable_columns`

#### `apply_changes`

Applies staged changes without finalizing the session if partial application is supported.

Request fields:

- `edit_session_id`
- `changeset`

Response fields:

- per-row outcomes
- refreshed row identities if needed
- validation errors

#### `commit_edit_session`

Commits the session transaction.

#### `rollback_edit_session`

Rolls back the session transaction.

#### `refresh_rows`

Refetches current row state from the database for one or more rows.

## 6. Event Types

Suggested initial event set:

- `log`
- `query_started`
- `query_progress`
- `query_schema`
- `query_page_ready`
- `query_completed`
- `query_failed`
- `edit_session_invalidated`

Events should carry a stable correlation key such as `query_id` or `edit_session_id`.

## 7. Query Result Shape

Query result payloads should normalize:

- column order
- column names
- logical type name
- nullability when available
- display formatting hints
- write metadata when relevant

Row payloads should avoid premature UI formatting when possible. Lua can format for presentation while preserving raw values or typed metadata.

## 8. Writability Payload

The worker must clearly explain why a result is or is not writable.

Suggested fields:

- `writable`
- `reason_code`
- `reason_message`
- `base_table`
- `row_identity_strategy`
- `required_refresh_behavior`
- `writable_columns`
- `restricted_columns`

This lets Lua provide precise UX instead of generic failure messages.

## 9. Logging Messages

The worker may emit non-fatal log events for debug mode.

Suggested levels:

- `error`
- `warn`
- `info`
- `debug`

Lua should be able to suppress or persist these depending on configuration.

## 10. Retry Philosophy

Protocol-level retries should be minimal and explicit.

Allowed examples:

- reconnect worker after crash
- reinstall worker after failed verification

Avoid automatic retries for writes or ambiguous query operations.

## 11. Protocol Design Constraints

- keep method names stable
- prefer explicit payloads over positional arguments
- preserve room for adapter-specific extensions without breaking the common contract
- always return enough context for Lua to present actionable status
