local config = require('deebee.config')

local M = {}

local state = {
  connections = {},
  active_connection_id = nil,
  active_session = nil,
  catalog = {
    root = {},
    schemas = {},
  },
  explorer_items = {},
  last_query = nil,
  result_grid = nil,
  workspace = nil,
}

local function connection_copy(connection)
  return vim.deepcopy(connection)
end

function M.refresh_connections()
  state.connections = vim.tbl_map(connection_copy, config.values.connections or {})
end

function M.connections()
  return state.connections
end

function M.connection_ids()
  local ids = {}
  for _, connection in ipairs(state.connections) do
    table.insert(ids, connection.id)
  end
  return ids
end

function M.get_connection(connection_id)
  for _, connection in ipairs(state.connections) do
    if connection.id == connection_id then
      return connection
    end
  end
end

function M.default_connection()
  if config.values.default_connection then
    return M.get_connection(config.values.default_connection)
  end

  if #state.connections == 1 then
    return state.connections[1]
  end
end

function M.set_active_session(connection, session)
  state.active_connection_id = connection.id
  state.active_session = vim.tbl_deep_extend('force', {}, session, {
    connection_id = connection.id,
    connection_name = connection.name,
  })
end

function M.active_connection()
  if not state.active_connection_id then
    return nil
  end
  return M.get_connection(state.active_connection_id)
end

function M.active_session()
  return state.active_session
end

function M.clear_active_session()
  state.active_connection_id = nil
  state.active_session = nil
  state.catalog = {
    root = {},
    schemas = {},
  }
  state.explorer_items = {}
  state.last_query = nil
  state.result_grid = nil
end

function M.set_catalog(root_nodes, schema_nodes)
  state.catalog = {
    root = root_nodes or {},
    schemas = schema_nodes or {},
  }
end

function M.catalog()
  return state.catalog
end

function M.set_explorer_items(items)
  state.explorer_items = items or {}
end

function M.explorer_items()
  return state.explorer_items
end

function M.set_last_query(query)
  state.last_query = query
end

function M.last_query()
  return state.last_query
end

function M.set_result_grid(grid)
  state.result_grid = grid
end

function M.result_grid()
  return state.result_grid
end

function M.set_workspace(workspace)
  state.workspace = workspace
end

function M.workspace()
  return state.workspace
end

return M
