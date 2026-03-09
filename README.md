# deebee.nvim

`deebee.nvim` is a Neovim database plugin built around a Lua frontend and a Rust worker.

The product target is a high-quality in-editor database workflow for PostgreSQL first and Oracle second, with a strong focus on inspection, query execution, and safe editable result grids for the common case.

Status: planning and implementation-spec phase.

## Core Decisions

- Neovim requirement: `0.11+`
- Frontend: `Lua`
- Backend worker: `Rust`
- Initial database target: `PostgreSQL`
- Follow-up target: `Oracle`
- Oracle support may require `Oracle Instant Client`
- Editable grids are limited to safe `single-table` result sets in v1
- Worker binaries are distributed as prebuilt release assets from this same repository
- Worker binaries auto-download on first use
- Plugin only accepts the exact pinned worker version
- Worker updates happen only on explicit user command

## Documentation

- `docs/implementation-spec.md` - source-of-truth product and implementation spec
- `docs/architecture.md` - component architecture, boundaries, and data flow
- `docs/rpc-protocol.md` - worker protocol, message shapes, lifecycle, and error model
- `docs/editable-grid-spec.md` - editable result grid behavior, safety rules, and edge cases
- `docs/release-distribution.md` - binary packaging, installer behavior, and release process
- `docs/roadmap.md` - milestone plan, release order, and acceptance criteria
- `docs/agent-handbook.md` - working rules for contributors and coding agents
- `docs/decision-log.md` - concise record of locked, planned, and still-open decisions
- `docs/configuration.md` - current setup shape, connection config, and development commands
- `docs/local-postgres-testing.md` - seeded Docker database and realistic test workflow

## Product Intent

The goal is not to clone DataGrip feature-for-feature. The goal is to build the best practical database workflow inside Neovim while preserving a strong UX for:

- browsing and inspecting schema objects
- running and canceling queries
- viewing large result sets smoothly
- taking notes and using SQL scratchpads
- editing data safely when the plugin can prove the query is writable

## V1 Shape

V1 means:

- PostgreSQL-first release
- explorer, query runner, notes, history, DDL inspection
- paged result grid
- editable single-table result grids with explicit commit and rollback
- prebuilt worker download and health checks

Oracle lands immediately after the PostgreSQL release using the same UI and edit-session model.

## Local Development

For local `lazy.nvim` development, use a repo directory entry similar to:

```lua
{
  dir = '/Users/kamil/Personal/Projects/deebee.nvim',
  name = 'deebee.nvim',
  opts = {},
}
```

If you want to run a locally built worker instead of the managed downloaded binary, set:

```lua
vim.g.deebee_worker_path = '/absolute/path/to/deebee-worker'
```

Basic setup example:

```lua
{
  dir = '/Users/kamil/Personal/Projects/deebee.nvim',
  name = 'deebee.nvim',
  opts = {
    default_connection = 'local',
    connections = {
      {
        id = 'local',
        name = 'Local Postgres',
        adapter = 'postgres',
        dsn = 'postgres://deebee:deebee@localhost:55432/deebee',
      },
    },
  },
}
```

For a seeded local test database, use `just pg-run` and see `docs/local-postgres-testing.md`.

Current commands:

- `:DeebeeOpen`
- `:DeebeeConnect [id]`
- `:DeebeeDisconnect`
- `:DeebeeRun`
- `:DeebeeNextPage`
- `:DeebeePrevPage`
- `:DeebeeRefreshExplorer`
- `:DeebeeInstall`
- `:DeebeeUpdateWorker`
- `:DeebeeWorkerInfo`

Current results grid behavior:

- readonly grid rendering with row numbers
- grouped query metadata above the table
- paged navigation via `:DeebeeNextPage`, `:DeebeePrevPage`, `]p`, and `[p`

Current explorer behavior:

- `Enter` on a schema or object group toggles expand/collapse
- `Tab` on a schema or object group toggles expand/collapse
- `Enter` on a table, view, or materialized view runs `select * from <schema>.<object>;`
- `Enter` on a connection line connects to that database
