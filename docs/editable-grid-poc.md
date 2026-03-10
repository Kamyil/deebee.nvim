# Editable Grid PoC

This document describes the temporary editable-grid prototype.

It is intentionally not the real implementation.

The goal is only to test whether the interaction model feels right inside the existing Neovim results buffer before building the worker-backed writable grid.

## What The PoC Is

- a Lua-only interaction prototype layered on top of the current results grid
- local staged cell edits on the current rendered page
- explicit commit and rollback actions
- no database writes

## What The PoC Is Not

- not safe write inference
- not worker-backed edit sessions
- not transaction control against PostgreSQL
- not proof that the final implementation details are settled

## Commands

- `:DeebeeEdit`
- `:DeebeeEditCell`
- `:DeebeeCommit`
- `:DeebeeRollback`
- `:DeebeeRevertRow`

## Buffer Keymaps

Inside the results buffer:

- `e` - toggle edit mode
- `<CR>` - enter edit mode or edit the current cell
- `<Tab>` - jump to the next cell in edit mode
- `<S-Tab>` - jump to the previous cell in edit mode
- `u` - revert the current row to the last local baseline
- `gC` - commit staged changes locally
- `gR` - roll back staged changes locally

## Behavior Notes

- query paging and rerun are blocked while the PoC has staged local changes
- committing only updates the local baseline inside the buffer
- rolling back restores the last local baseline
- typing `NULL` in the cell prompt stores a null-like display value in the PoC model

## Recommended Test Flow

1. Run one of the simple table queries from `docs/local-postgres-testing.md`.
2. Press `e` in the results grid.
3. Move with normal motions or `<Tab>`.
4. Press `<CR>` to edit a cell.
5. Try `gC` and `gR` to see whether the staged-change model feels natural.

## Why This Exists

The long-term architecture still expects:

- Lua-owned grid UX
- worker-owned writability and DML logic
- explicit commit and rollback

This PoC exists only to validate the UX shape before that full implementation work starts.
