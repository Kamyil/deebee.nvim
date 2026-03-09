local config = require('deebee.config')
local grid = require('deebee.grid.results')
local state = require('deebee.state')

local M = {}

local function is_valid_buffer(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function is_valid_window(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function configure_scratch_buffer(buf, name, filetype)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = filetype or ''
  vim.api.nvim_buf_set_name(buf, name)
end

local function create_workspace()
  vim.cmd('tabnew')

  local query_win = vim.api.nvim_get_current_win()
  local query_buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(query_win, query_buf)
  vim.bo[query_buf].buftype = 'nofile'
  vim.bo[query_buf].bufhidden = 'hide'
  vim.bo[query_buf].swapfile = false
  vim.bo[query_buf].filetype = 'sql'
  vim.api.nvim_buf_set_name(query_buf, 'deebee://query')
  vim.api.nvim_buf_set_lines(query_buf, 0, -1, false, {
    '-- Write SQL here and run :DeebeeRun',
    '-- Use :DeebeeConnect <id> if you have multiple configured connections.',
    '',
    'select current_database();',
  })

  vim.cmd('topleft vnew')
  local explorer_win = vim.api.nvim_get_current_win()
  local explorer_buf = vim.api.nvim_create_buf(false, true)
  configure_scratch_buffer(explorer_buf, 'deebee://explorer', 'deebee-explorer')
  vim.api.nvim_win_set_buf(explorer_win, explorer_buf)
  vim.api.nvim_win_set_width(explorer_win, config.values.workspace.explorer_width)
  vim.wo[explorer_win].winfixwidth = true
  vim.bo[explorer_buf].modifiable = false
  vim.bo[explorer_buf].readonly = false
  vim.bo[explorer_buf].buflisted = false
  vim.keymap.set('n', '<CR>', '<Cmd>DeebeeExplorerOpen<CR>', {
    buffer = explorer_buf,
    silent = true,
    desc = 'Open explorer item',
  })
  vim.keymap.set('n', '<Tab>', '<Cmd>DeebeeExplorerToggle<CR>', {
    buffer = explorer_buf,
    silent = true,
    desc = 'Toggle explorer node',
  })
  vim.keymap.set('n', 'za', '<Cmd>DeebeeExplorerToggle<CR>', {
    buffer = explorer_buf,
    silent = true,
    desc = 'Toggle explorer node',
  })
  vim.keymap.set('n', 'zo', '<Cmd>DeebeeExplorerExpand<CR>', {
    buffer = explorer_buf,
    silent = true,
    desc = 'Expand explorer node',
  })
  vim.keymap.set('n', 'zc', '<Cmd>DeebeeExplorerCollapse<CR>', {
    buffer = explorer_buf,
    silent = true,
    desc = 'Collapse explorer node',
  })

  vim.api.nvim_set_current_win(query_win)
  vim.cmd('botright vnew')
  local results_win = vim.api.nvim_get_current_win()
  local results_buf = vim.api.nvim_create_buf(false, true)
  local available_width = math.max(20, vim.o.columns - config.values.workspace.explorer_width - 3)
  local preferred_results_width = config.values.workspace.results_width or math.floor(available_width / 2)
  local results_width = math.max(20, math.min(preferred_results_width, math.floor(available_width / 2)))
  configure_scratch_buffer(results_buf, 'deebee://results', 'deebee-results')
  grid.setup_buffer(results_buf)
  vim.api.nvim_win_set_buf(results_win, results_buf)
  vim.api.nvim_win_set_width(results_win, results_width)
  vim.wo[results_win].wrap = false
  vim.wo[results_win].number = false
  vim.wo[results_win].relativenumber = false
  vim.wo[results_win].cursorline = true

  vim.api.nvim_set_current_win(query_win)

  local workspace = {
    tab = vim.api.nvim_get_current_tabpage(),
    windows = {
      explorer = explorer_win,
      query = query_win,
      results = results_win,
    },
    buffers = {
      explorer = explorer_buf,
      query = query_buf,
      results = results_buf,
    },
  }

  state.set_workspace(workspace)
  return workspace
end

function M.ensure_open()
  local workspace = state.workspace()
  if workspace
    and is_valid_buffer(workspace.buffers.explorer)
    and is_valid_buffer(workspace.buffers.query)
    and is_valid_buffer(workspace.buffers.results)
    and is_valid_window(workspace.windows.query)
  then
    return workspace
  end

  return create_workspace()
end

local function set_buffer_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

function M.render_explorer(lines)
  local workspace = M.ensure_open()
  set_buffer_lines(workspace.buffers.explorer, lines)
end

function M.render_results(result)
  local workspace = M.ensure_open()
  grid.render(workspace.buffers.results, result)
end

function M.focus_query()
  local workspace = M.ensure_open()
  vim.api.nvim_set_current_win(workspace.windows.query)
end

function M.current_query_buffer()
  local workspace = M.ensure_open()
  return workspace.buffers.query
end

function M.focus_explorer()
  local workspace = M.ensure_open()
  vim.api.nvim_set_current_win(workspace.windows.explorer)
end

function M.set_query_lines(lines)
  local workspace = M.ensure_open()
  vim.api.nvim_buf_set_lines(workspace.buffers.query, 0, -1, false, lines)
end

return M
