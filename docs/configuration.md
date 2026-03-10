# Configuration

This document describes the current configuration surface.

The configuration is intentionally small at this stage because the implementation is still in Milestone 0 / early Milestone 1.

## 1. Setup

Call `require('deebee').setup({ ... })` from your plugin manager config.

Example:

```lua
require('deebee').setup({
  default_connection = 'local',
  query_page_size = 100,
  connections = {
    {
      id = 'local',
      name = 'Local Postgres',
      adapter = 'postgres',
      dsn = 'postgres://deebee:deebee@localhost:55432/deebee',
    },
  },
})
```

If you use the seeded Docker database from this repository, start it with `just pg-run` first.

## 2. Supported Options

### `default_connection`

- type: `string | nil`
- behavior: if set, `:DeebeeOpen` and `:DeebeeRun` can use this connection automatically

### `query_page_size`

- type: `integer`
- default: `100`
- behavior: number of rows fetched into one rendered page from the worker cache

### `connections`

- type: `table[]`
- default: `{}`

Each connection currently supports:

- `id` - stable connection id used by `:DeebeeConnect`
- `name` - display label in the explorer
- `adapter` - currently only `postgres` is implemented
- `dsn` or `url` - PostgreSQL connection string

If `id` is omitted, the plugin will derive it from `name` or the connection index.

## 3. Worker Overrides

For local development you can bypass the managed downloaded worker and point the plugin to a locally built binary.

```lua
vim.g.deebee_worker_path = '/absolute/path/to/deebee-worker'
```

This is especially useful while iterating on the Rust worker locally.

## 4. Current Commands

- `:DeebeeOpen` - open the workspace shell
- `:DeebeeConnect [id]` - connect to a configured database
- `:DeebeeDisconnect` - disconnect the active session
- `:DeebeeRun` - run SQL from the current buffer
- `:DeebeeNextPage` - move to the next cached result page
- `:DeebeePrevPage` - move to the previous cached result page
- `:DeebeeEdit` - toggle the experimental local-only editable-grid PoC for the current results page
- `:DeebeeEditCell` - edit the cell under the cursor while the PoC is in edit mode
- `:DeebeeCommit` - commit staged PoC changes locally in the results buffer
- `:DeebeeRollback` - roll back staged PoC changes to the last local baseline
- `:DeebeeRevertRow` - revert the current row to the last local baseline
- `:DeebeeRefreshExplorer` - reload explorer data for the active session
- `:DeebeeExplorerOpen` - open the explorer item under the cursor
- `:DeebeeExplorerToggle` - toggle the explorer node under the cursor
- `:DeebeeExplorerExpand` - expand the explorer node under the cursor
- `:DeebeeExplorerCollapse` - collapse the explorer node under the cursor
- `:DeebeeInstall` - ensure the pinned worker is installed
- `:DeebeeUpdateWorker` - reinstall the pinned worker explicitly
- `:DeebeeWorkerInfo` - inspect worker resolution and version info

Explorer keymaps:

- `<CR>` on a schema or object group toggles expand/collapse
- `<Tab>` on a schema or object group toggles expand/collapse
- `<CR>` on a connection line connects to it
- `<CR>` on a table, view, or materialized view line runs `select * from schema.object;`
- `za` toggles the current schema or object group
- `zo` expands the current schema or object group
- `zc` collapses the current schema or object group

## 5. Current Limits

At the current implementation stage:

- only PostgreSQL is implemented
- queries are cached in worker memory after execution
- result paging is worker-cache paging, not database-cursor paging yet
- explorer currently shows configured connections and loaded schemas with grouped views, materialized views, and tables
- results render into a scratch grid buffer with row numbers and paged navigation
- results buffer keymaps include `]p` for next page, `[p` for previous page, and `gr` to rerun the current query
- results buffer also includes an experimental local-only editable-grid PoC: `e` toggles edit mode, `<CR>` edits the current cell, `<Tab>` and `<S-Tab>` move between cells, `u` reverts the current row, `gC` commits locally, and `gR` rolls back locally
- the editable-grid PoC does not write to the database yet; it exists only to test the interaction feel before the real worker-backed implementation lands

See `docs/editable-grid-poc.md` for the temporary prototype behavior.

These are expected intermediate constraints while Milestone 1 is being built out.
