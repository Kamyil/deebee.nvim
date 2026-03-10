local notify = require('deebee.notify')
local config = require('deebee.config')
local grid = require('deebee.grid.results')
local state = require('deebee.state')
local workspace = require('deebee.ui.workspace')
local worker = require('deebee.worker')

local M = {}

local icons = {
  connections = '󰆼',
  connection = '󰈆',
  schemas = '󰙅',
  schema = '󰌗',
  view_group = '󰈈',
  materialized_view_group = '󰍹',
  table_group = '󰓫',
  view = '󰈈',
  materialized_view = '󰍹',
  table = '󰓫',
  commands = '󰘳',
  command = '󰘳',
  expanded = '',
  collapsed = '',
}

local explorer_labels = {
  view = 'Views',
  materialized_view = 'Materialized Views',
  table = 'Tables',
}

local explorer_order = { 'view', 'materialized_view', 'table' }

local function with_error_boundary(fn)
  local ok, result = pcall(fn)
  if not ok then
    notify.error(result)
    return nil
  end
  return result
end

function M.install()
  with_error_boundary(function()
    local handshake = worker.ensure_running()
    notify.info(string.format('Worker %s is ready.', handshake.worker_version))
  end)
end

local function render_explorer()
  local lines = {
    icons.connections .. ' deebee.nvim',
    '',
    icons.connections .. ' Connections',
  }
  local explorer_items = {}

  local function push_line(text, item)
    table.insert(lines, text)
    explorer_items[#lines] = item
  end

  local function object_icon(kind)
    return icons[kind] or '•'
  end

  local active_connection = state.active_connection()
  local active_session = state.active_session()

  for _, connection in ipairs(state.connections()) do
    local prefix = active_connection and active_connection.id == connection.id and '*' or ' '
    local suffix = ''
    if active_session and active_session.connection_id == connection.id then
      suffix = ' [connected]'
    end
    push_line(string.format('%s %s %s (%s)%s', prefix, icons.connection, connection.name, connection.adapter, suffix), {
      kind = 'connection',
      connection_id = connection.id,
      adapter = connection.adapter,
    })
  end

  if #state.connections() == 0 then
    push_line('  no configured connections')
  end

  push_line('')

  if active_session then
    push_line(icons.schemas .. ' Schemas')
    local catalog = state.catalog()
    for _, schema in ipairs(catalog.root or {}) do
      local schema_expanded = state.schema_expanded(schema.name)
      push_line(string.format('  %s %s %s', schema_expanded and icons.expanded or icons.collapsed, icons.schema, schema.name), {
        kind = 'schema',
        schema = schema.name,
        expanded = schema_expanded,
      })

      local objects = catalog.schemas and catalog.schemas[schema.name] or {}
      local grouped = {}
      for _, object in ipairs(objects) do
        grouped[object.kind] = grouped[object.kind] or {}
        table.insert(grouped[object.kind], object)
      end

      local present_groups = {}
      for _, kind in ipairs(explorer_order) do
        if grouped[kind] and #grouped[kind] > 0 then
          table.insert(present_groups, kind)
        end
      end

      for _, kind in ipairs(present_groups) do
        local entries = grouped[kind]
        local group_expanded = state.group_expanded(schema.name, kind)

        if schema_expanded then
          push_line(string.format('    %s %s %s', group_expanded and icons.expanded or icons.collapsed, object_icon(kind .. '_group'), explorer_labels[kind]), {
            kind = 'group',
            schema = schema.name,
            object_kind = kind,
            expanded = group_expanded,
          })
        end

        if schema_expanded and group_expanded then
          for _, object in ipairs(entries) do
            push_line(string.format('      %s %s', object_icon(object.kind), object.name), {
              kind = 'object',
              schema = schema.name,
              object_kind = object.kind,
              name = object.name,
              path = object.path,
            })
          end
        end
      end
    end
    if #(catalog.root or {}) == 0 then
      push_line('  · no schemas loaded')
    end
  else
    push_line('  · No active database session')
  end

  push_line('')
  push_line(icons.commands .. ' Commands')
  push_line('  ' .. icons.command .. ' :DeebeeConnect [id]')
  push_line('  ' .. icons.command .. ' :DeebeeRun')
  push_line('  ' .. icons.command .. ' :DeebeeNextPage / :DeebeePrevPage')

  state.set_explorer_items(explorer_items)
  workspace.render_explorer(lines)
end

local function refresh_catalog()
  local active_session = state.active_session()
  if not active_session then
    state.set_catalog({}, {})
    render_explorer()
    return
  end

  local root = worker.list_catalog(active_session.session_id, 'root', {}).nodes or {}
  local schemas = {}

  for _, schema in ipairs(root) do
    local response = worker.list_catalog(active_session.session_id, 'schema', { schema.name })
    schemas[schema.name] = response.nodes or {}
  end

  state.set_catalog(root, schemas)
  state.sync_explorer_expansion()
  render_explorer()
end

local function resolve_connection(connection_id)
  if connection_id and connection_id ~= '' then
    local connection = state.get_connection(connection_id)
    if connection then
      return connection
    end
    error('Unknown connection id: ' .. connection_id)
  end

  local default = state.default_connection()
  if default then
    return default
  end

  error('No default connection is available. Configure one connection or pass a connection id.')
end

local function current_sql()
  local current_buf = vim.api.nvim_get_current_buf()
  local workspace_state = state.workspace()
  if workspace_state and workspace_state.buffers and current_buf ~= workspace_state.buffers.query then
    current_buf = workspace_state.buffers.query
  end

  local mode = vim.fn.mode()
  if mode == 'v' or mode == 'V' or mode == '\22' then
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local lines = vim.api.nvim_buf_get_lines(current_buf, start_pos[2] - 1, end_pos[2], false)
    if #lines == 0 then
      return ''
    end
    lines[1] = lines[1]:sub(start_pos[3])
    lines[#lines] = lines[#lines]:sub(1, end_pos[3])
    return table.concat(lines, '\n')
  end

  return table.concat(vim.api.nvim_buf_get_lines(current_buf, 0, -1, false), '\n')
end

local function results_buffer()
  local workspace_state = state.workspace()
  if not workspace_state or not workspace_state.buffers or not workspace_state.buffers.results then
    error('Results grid is not open.')
  end

  return workspace_state.buffers.results
end

local function ensure_results_grid_not_dirty(action)
  local workspace_state = state.workspace()
  local buf = workspace_state and workspace_state.buffers and workspace_state.buffers.results or nil
  if buf and grid.has_pending_changes(buf) then
    error(string.format(
      'Editable-grid PoC has staged local changes. Commit or rollback before %s.',
      action or 'continuing'
    ))
  end
end

local function quote_ident(identifier)
  return '"' .. tostring(identifier):gsub('"', '""') .. '"'
end

local function run_object_select(item)
  local qualified_name = quote_ident(item.schema) .. '.' .. quote_ident(item.name)
  workspace.set_query_lines({ 'select * from ' .. qualified_name .. ';' })
  workspace.focus_query()
  M.run_query()
end

local function explorer_item_at_cursor()
  local workspace_state = state.workspace()
  if not workspace_state or not workspace_state.windows or not workspace_state.windows.explorer then
    error('Explorer is not open.')
  end

  local current_win = vim.api.nvim_get_current_win()
  if current_win ~= workspace_state.windows.explorer then
    vim.api.nvim_set_current_win(workspace_state.windows.explorer)
  end

  local line = vim.api.nvim_win_get_cursor(workspace_state.windows.explorer)[1]
  return state.explorer_items()[line]
end

local function set_expanded(item, expanded)
  if item.kind == 'schema' then
    state.set_schema_expanded(item.schema, expanded)
    render_explorer()
    return true
  end

  if item.kind == 'group' then
    state.set_group_expanded(item.schema, item.object_kind, expanded)
    render_explorer()
    return true
  end

  return false
end

local function toggle_expanded(item)
  if item.kind == 'schema' then
    state.toggle_schema_expanded(item.schema)
    render_explorer()
    return true
  end

  if item.kind == 'group' then
    state.toggle_group_expanded(item.schema, item.object_kind)
    render_explorer()
    return true
  end

  return false
end

function M.update_worker()
  with_error_boundary(function()
    worker.stop()
    local worker_path = require('deebee.installer').install({ force = true })
    local handshake = worker.ensure_running()
    notify.info(string.format('Reinstalled worker at %s (%s).', worker_path, handshake.worker_version))
  end)
end

function M.open()
  with_error_boundary(function()
    worker.ensure_running()
    workspace.ensure_open()
    render_explorer()

    local default = state.default_connection()
    if default and not state.active_session() then
      M.connect(default.id)
      return
    end

    workspace.focus_query()
    notify.info('deebee workspace is ready.')
  end)
end

function M.connect(connection_id)
  with_error_boundary(function()
    local connection = resolve_connection(connection_id)
    local session = worker.connect(connection)
    state.set_active_session(connection, session)
    workspace.ensure_open()
    refresh_catalog()
    workspace.focus_query()
    notify.info('Connected to ' .. connection.name)
  end)
end

function M.disconnect()
  with_error_boundary(function()
    local active_session = state.active_session()
    if not active_session then
      notify.warn('No active database session.')
      return
    end

    worker.disconnect(active_session.session_id)
    state.clear_active_session()
    render_explorer()
    notify.info('Disconnected from database session.')
  end)
end

function M.run_query()
  with_error_boundary(function()
    ensure_results_grid_not_dirty('rerunning the query')

    local active_session = state.active_session()
    if not active_session then
      local default = state.default_connection()
      if default then
        M.connect(default.id)
        active_session = state.active_session()
      end
    end

    if not active_session then
      error('No active connection. Run :DeebeeConnect first.')
    end

    local sql = current_sql()
    local result = worker.run_query(active_session.session_id, sql, config.values.query_page_size)
    result.page_index = result.page and result.page.page_index or 0
    state.set_last_query(result)
    state.set_result_grid(result.page or result)
    workspace.render_results(result)
    render_explorer()
    notify.info('Query finished.')
  end)
end

local function move_page(delta)
  with_error_boundary(function()
    ensure_results_grid_not_dirty('changing result pages')

    local last_query = state.last_query()
    if not last_query then
      error('No query has been executed yet.')
    end

    local current_page = last_query.page and last_query.page.page_index or last_query.page_index or 0
    local next_page = math.max(0, current_page + delta)
    if delta > 0 and last_query.page and not last_query.page.has_more then
      notify.warn('Already at the last page.')
      return
    end
    if delta < 0 and current_page == 0 then
      notify.warn('Already at the first page.')
      return
    end

    local page = worker.fetch_page(last_query.query_id, next_page)
    last_query.page = page
    last_query.page_index = page.page_index
    state.set_last_query(last_query)
    state.set_result_grid(page)
    workspace.render_results(last_query)
  end)
end

function M.next_page()
  move_page(1)
end

function M.prev_page()
  move_page(-1)
end

function M.refresh_explorer()
  with_error_boundary(function()
    workspace.ensure_open()
    refresh_catalog()
  end)
end

function M.explorer_open()
  with_error_boundary(function()
    local item = explorer_item_at_cursor()
    if not item then
      notify.warn('No explorer action for this line.')
      return
    end

    if toggle_expanded(item) then
      return
    end

    if item.kind == 'connection' then
      M.connect(item.connection_id)
      return
    end

    if item.kind == 'object' and (item.object_kind == 'table' or item.object_kind == 'view' or item.object_kind == 'materialized_view') then
      run_object_select(item)
      return
    end

    notify.warn('Nothing to open on this line yet.')
  end)
end

function M.explorer_toggle()
  with_error_boundary(function()
    local item = explorer_item_at_cursor()
    if not item then
      notify.warn('No explorer node on this line.')
      return
    end

    if toggle_expanded(item) then
      return
    end

    notify.warn('This explorer item cannot be toggled.')
  end)
end

function M.explorer_expand()
  with_error_boundary(function()
    local item = explorer_item_at_cursor()
    if not item then
      notify.warn('No explorer node on this line.')
      return
    end

    if set_expanded(item, true) then
      return
    end

    notify.warn('This explorer item cannot be expanded.')
  end)
end

function M.explorer_collapse()
  with_error_boundary(function()
    local item = explorer_item_at_cursor()
    if not item then
      notify.warn('No explorer node on this line.')
      return
    end

    if set_expanded(item, false) then
      return
    end

    notify.warn('This explorer item cannot be collapsed.')
  end)
end

function M.worker_info()
  local info = with_error_boundary(function()
    return worker.info()
  end)

  if not info then
    return
  end

  notify.info(vim.inspect(info))
end

function M.edit_results()
  with_error_boundary(function()
    grid.toggle_edit_mode(results_buffer())
  end)
end

function M.edit_results_cell()
  with_error_boundary(function()
    grid.edit_cell(results_buffer())
  end)
end

function M.commit_results()
  with_error_boundary(function()
    grid.commit(results_buffer())
  end)
end

function M.rollback_results()
  with_error_boundary(function()
    grid.rollback(results_buffer())
  end)
end

function M.revert_results_row()
  with_error_boundary(function()
    grid.revert_row(results_buffer())
  end)
end

function M.stop_worker()
  worker.stop()
  notify.info('Worker stopped.')
end

function M.register()
  vim.api.nvim_create_user_command('DeebeeInstall', function()
    M.install()
  end, {})

  vim.api.nvim_create_user_command('DeebeeOpen', function()
    M.open()
  end, {})

  vim.api.nvim_create_user_command('DeebeeConnect', function(opts)
    M.connect(opts.args)
  end, {
    nargs = '?',
    complete = function()
      return state.connection_ids()
    end,
  })

  vim.api.nvim_create_user_command('DeebeeDisconnect', function()
    M.disconnect()
  end, {})

  vim.api.nvim_create_user_command('DeebeeRun', function()
    M.run_query()
  end, {
    range = true,
  })

  vim.api.nvim_create_user_command('DeebeeRefreshExplorer', function()
    M.refresh_explorer()
  end, {})

  vim.api.nvim_create_user_command('DeebeeExplorerOpen', function()
    M.explorer_open()
  end, {})

  vim.api.nvim_create_user_command('DeebeeExplorerToggle', function()
    M.explorer_toggle()
  end, {})

  vim.api.nvim_create_user_command('DeebeeExplorerExpand', function()
    M.explorer_expand()
  end, {})

  vim.api.nvim_create_user_command('DeebeeExplorerCollapse', function()
    M.explorer_collapse()
  end, {})

  vim.api.nvim_create_user_command('DeebeeNextPage', function()
    M.next_page()
  end, {})

  vim.api.nvim_create_user_command('DeebeePrevPage', function()
    M.prev_page()
  end, {})

  vim.api.nvim_create_user_command('DeebeeEdit', function()
    M.edit_results()
  end, {})

  vim.api.nvim_create_user_command('DeebeeEditCell', function()
    M.edit_results_cell()
  end, {})

  vim.api.nvim_create_user_command('DeebeeCommit', function()
    M.commit_results()
  end, {})

  vim.api.nvim_create_user_command('DeebeeRollback', function()
    M.rollback_results()
  end, {})

  vim.api.nvim_create_user_command('DeebeeRevertRow', function()
    M.revert_results_row()
  end, {})

  vim.api.nvim_create_user_command('DeebeeWorkerInfo', function()
    M.worker_info()
  end, {})

  vim.api.nvim_create_user_command('DeebeeUpdateWorker', function()
    M.update_worker()
  end, {})

  vim.api.nvim_create_user_command('DeebeeStopWorker', function()
    M.stop_worker()
  end, {})
end

return M
