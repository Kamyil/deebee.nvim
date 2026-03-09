local constants = require('deebee.constants')

local M = {}

M.values = {
  worker_version = constants.worker_version,
  protocol_version = constants.protocol_version,
  github_repo = constants.github_repo,
  worker_path = nil,
  install_root = vim.fn.stdpath('data') .. '/deebee/bin',
  download_timeout_ms = 120000,
  query_page_size = 100,
  connections = {},
  default_connection = nil,
  workspace = {
    explorer_width = 32,
    results_height = 14,
  },
}

local function normalize_connection(connection, index)
  local normalized = vim.tbl_deep_extend('force', {
    adapter = 'postgres',
  }, connection or {})

  normalized.id = normalized.id or normalized.name or ('connection-' .. index)
  normalized.name = normalized.name or normalized.id
  normalized.dsn = normalized.dsn or normalized.url
  normalized.url = normalized.url or normalized.dsn

  return normalized
end

function M.setup(opts)
  M.values = vim.tbl_deep_extend('force', M.values, opts or {})

  local normalized_connections = {}
  for index, connection in ipairs(M.values.connections or {}) do
    table.insert(normalized_connections, normalize_connection(connection, index))
  end
  M.values.connections = normalized_connections

  return M.values
end

return M
