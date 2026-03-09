local commands = require('deebee.commands')
local config = require('deebee.config')
local state = require('deebee.state')

local M = {}

local did_setup = false

function M.setup(opts)
  config.setup(opts)
  state.refresh_connections()

  if not did_setup then
    commands.register()
    did_setup = true
  end

  return config.values
end

function M.open()
  require('deebee.commands').open()
end

return M
