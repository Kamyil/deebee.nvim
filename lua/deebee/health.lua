local config = require('deebee.config')
local constants = require('deebee.constants')
local installer = require('deebee.installer')
local util = require('deebee.util')
local worker = require('deebee.worker')

local M = {}

function M.check()
  vim.health.start('deebee.nvim')
  vim.health.ok('Neovim version is ' .. vim.version().major .. '.' .. vim.version().minor)
  vim.health.info('Plugin version: ' .. constants.plugin_version)
  vim.health.info('Expected worker version: ' .. config.values.worker_version)
  vim.health.info('Protocol version: ' .. tostring(config.values.protocol_version))
  vim.health.info('Configured connections: ' .. tostring(#(config.values.connections or {})))

  local target_ok, target = pcall(util.target_triple)
  if target_ok then
    vim.health.ok('Detected target: ' .. target)
  else
    vim.health.error(target)
    return
  end

  local path, source = installer.resolve_worker_path()
  vim.health.info('Worker source: ' .. source)
  vim.health.info('Resolved worker path: ' .. path)

  if util.executable(path) then
    vim.health.ok('Worker binary is present.')
  else
    vim.health.warn('Worker binary is not installed yet. It will auto-download on first use.')
  end

  local ok, result = pcall(worker.health)
  if ok then
    vim.health.ok('Worker handshake succeeded.')
    vim.health.info('Worker runtime: ' .. result.runtime.os .. '/' .. result.runtime.arch)
    vim.health.info('Worker sessions: ' .. tostring(result.sessions or 0))

    local postgres = result.adapters and result.adapters.postgres or nil
    local oracle = result.adapters and result.adapters.oracle or nil

    if postgres and postgres.available then
      vim.health.ok('Postgres adapter is available.')
    elseif postgres then
      vim.health.info('Postgres adapter status: ' .. postgres.reason)
    end

    if oracle and oracle.available then
      vim.health.ok('Oracle adapter is available.')
    elseif oracle then
      vim.health.info('Oracle adapter status: ' .. oracle.reason)
    end
  else
    vim.health.warn('Worker health request failed: ' .. result)
  end
end

return M
