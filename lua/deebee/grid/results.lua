local notify = require('deebee.notify')

local M = {}

local namespace = vim.api.nvim_create_namespace('deebee-results-grid')
local models = {}

local function is_null(value)
  return value == nil or value == vim.NIL
end

local function stringify_cell(value)
  if is_null(value) then
    return 'NULL'
  end

  if type(value) == 'boolean' then
    return value and 'true' or 'false'
  end

  if type(value) == 'table' then
    return vim.json.encode(value)
  end

  return tostring(value)
end

local function display_value_for_input(value)
  if is_null(value) then
    return 'NULL'
  end

  return stringify_cell(value)
end

local function normalize_input_value(value)
  if value and value:upper() == 'NULL' then
    return vim.NIL
  end

  return value
end

local function is_numeric(value)
  return type(value) == 'number' or (type(value) == 'string' and value:match('^%-?%d+[%.%d]*$') ~= nil)
end

local function truncate(value, max_width)
  if vim.fn.strdisplaywidth(value) <= max_width then
    return value
  end

  if max_width <= 3 then
    return string.rep('.', max_width)
  end

  return vim.fn.strcharpart(value, 0, max_width - 3) .. '...'
end

local function pad(value, width, align_right)
  local display_width = vim.fn.strdisplaywidth(value)
  local padding = string.rep(' ', math.max(0, width - display_width))
  if align_right then
    return padding .. value
  end
  return value .. padding
end

local function set_buffer_lines(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function highlight_line(buf, line, group)
  vim.api.nvim_buf_add_highlight(buf, namespace, group, line, 0, -1)
end

local function clone_rows(rows)
  return vim.deepcopy(rows or {})
end

local function values_equal(left, right)
  if is_null(left) and is_null(right) then
    return true
  end

  if type(left) == 'table' or type(right) == 'table' then
    return vim.deep_equal(left, right)
  end

  return left == right
end

local function cell_is_dirty(model, row_index, column_index)
  local row = model.rows[row_index] or {}
  local baseline_row = model.baseline_rows[row_index] or {}
  return not values_equal(row[column_index], baseline_row[column_index])
end

local function row_is_dirty(model, row_index)
  for column_index = 1, #model.columns do
    if cell_is_dirty(model, row_index, column_index) then
      return true
    end
  end

  return false
end

local function dirty_counts(model)
  local dirty_cells = 0
  local dirty_rows = 0

  for row_index = 1, #model.rows do
    local row_dirty = false
    for column_index = 1, #model.columns do
      if cell_is_dirty(model, row_index, column_index) then
        dirty_cells = dirty_cells + 1
        row_dirty = true
      end
    end

    if row_dirty then
      dirty_rows = dirty_rows + 1
    end
  end

  return dirty_cells, dirty_rows
end

local function build_initial_model(result)
  local page = result.page or result
  local rows = clone_rows(page.rows or {})
  local total_rows = result.row_count or page.total_rows or #rows
  local page_index = page.page_index or 0
  local page_size = page.page_size or #rows
  local first_row = total_rows == 0 and 0 or (page_index * page_size) + 1
  local last_row = total_rows == 0 and 0 or math.min(first_row + #rows - 1, total_rows)

  return {
    query_id = result.query_id or page.query_id or '?',
    command_tag = result.command_tag,
    columns = vim.deepcopy(page.columns or result.columns or {}),
    rows = rows,
    baseline_rows = clone_rows(rows),
    total_rows = total_rows,
    page_index = page_index,
    page_size = page_size,
    has_more = page.has_more == true,
    first_row = first_row,
    last_row = last_row,
    mode = 'view',
    focus = nil,
    local_edit_supported = #(page.columns or result.columns or {}) > 0,
  }
end

local function build_controls_line(model)
  if not model.local_edit_supported then
    return 'Controls: ]p/[p page | gr rerun | tabular edit PoC requires rows and columns'
  end

  if model.mode == 'edit' then
    return 'Controls: e view | <CR> edit cell | <Tab>/<S-Tab> move | u revert row | gC commit | gR rollback'
  end

  return 'Controls: e edit | ]p/[p page | gr rerun | gC commit | gR rollback'
end

local function build_mode_line(model)
  if not model.local_edit_supported then
    return 'Mode: View | Read-only | Session: no editable cells on this result'
  end

  local dirty_cells, dirty_rows = dirty_counts(model)
  local mode_label = model.mode == 'edit' and 'Edit' or 'View'
  local session_label = dirty_cells == 0
      and 'clean'
    or string.format('%d dirty cells across %d rows', dirty_cells, dirty_rows)

  return string.format('Mode: %s | PoC local-only edit | Session: %s', mode_label, session_label)
end

local function format_table_line(values)
  local line = '|'
  local ranges = {}
  local line_width = #line

  for index, value in ipairs(values) do
    line = line .. ' '
    line_width = line_width + 1
    local start_col = line_width

    line = line .. value
    line_width = line_width + #value
    ranges[index] = {
      start_col = start_col,
      end_col = line_width,
    }

    line = line .. ' |'
    line_width = line_width + 2
  end

  return line, ranges
end

local function refresh_layout(model)
  local columns = model.columns
  local rows = model.rows
  local row_number_width = math.max(3, #tostring(math.max(model.last_row, #rows, 1)))
  local widths = { 1, row_number_width }
  local align_right = { false, true }
  local lines = {
    string.format('Query %s', model.query_id),
    string.format(
      'Rows %d-%d of %d | Page %d | Page size %d%s',
      model.first_row,
      model.last_row,
      model.total_rows,
      model.page_index + 1,
      model.page_size,
      model.has_more and ' | More rows available' or ''
    ),
    build_mode_line(model),
    build_controls_line(model),
  }

  if model.command_tag then
    table.insert(lines, 'Command tag: ' .. model.command_tag)
  end

  local preface_line_count = #lines

  if #columns == 0 then
    table.insert(lines, '')
    table.insert(lines, '[No tabular rows returned]')

    model.lines = lines
    model.preface_line_count = preface_line_count
    model.header_line = nil
    model.separator_line = nil
    model.data_start = #lines + 1
    model.state_ranges = {}
    model.cell_ranges = {}
    return
  end

  for index, column in ipairs(columns) do
    widths[index + 2] = math.min(math.max(vim.fn.strdisplaywidth(column), 6), 32)
    align_right[index + 2] = false
  end

  for _, row in ipairs(rows) do
    for index = 1, #columns do
      local text = stringify_cell(row[index])
      widths[index + 2] = math.min(math.max(widths[index + 2] or 6, vim.fn.strdisplaywidth(text)), 32)
      if is_numeric(row[index]) then
        align_right[index + 2] = true
      end
    end
  end

  table.insert(lines, '')
  local header_line = #lines + 1

  local header_cells = {
    pad('S', widths[1], false),
    pad('#', widths[2], true),
  }
  for index, column in ipairs(columns) do
    table.insert(header_cells, pad(column, widths[index + 2], false))
  end
  local header_text = format_table_line(header_cells)
  table.insert(lines, header_text)

  local separator_cells = {}
  for _, width in ipairs(widths) do
    table.insert(separator_cells, string.rep('-', width))
  end
  local separator_text = '|-' .. table.concat(separator_cells, '-|-') .. '-|'
  table.insert(lines, separator_text)

  local data_start = #lines + 1
  local state_ranges = {}
  local cell_ranges = {}

  if #rows == 0 then
    local empty_cells = {
      pad(' ', widths[1], false),
      pad('0', widths[2], true),
      pad('[no rows]', math.max(9, widths[3] or 9), false),
    }
    table.insert(lines, format_table_line(empty_cells))
  else
    for row_index, row in ipairs(rows) do
      local row_cells = {
        pad(row_is_dirty(model, row_index) and '*' or ' ', widths[1], false),
        pad(tostring(model.first_row + row_index - 1), widths[2], true),
      }

      for column_index = 1, #columns do
        local text = truncate(stringify_cell(row[column_index]), widths[column_index + 2])
        table.insert(row_cells, pad(text, widths[column_index + 2], align_right[column_index + 2]))
      end

      local line, ranges = format_table_line(row_cells)
      table.insert(lines, line)
      state_ranges[row_index] = ranges[1]
      cell_ranges[row_index] = {}
      for column_index = 1, #columns do
        cell_ranges[row_index][column_index] = ranges[column_index + 2]
      end
    end
  end

  model.lines = lines
  model.preface_line_count = preface_line_count
  model.header_line = header_line
  model.separator_line = header_line + 1
  model.data_start = data_start
  model.state_ranges = state_ranges
  model.cell_ranges = cell_ranges
end

local function apply_highlights(buf, model)
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  highlight_line(buf, 0, 'Title')

  for line = 1, model.preface_line_count - 1 do
    highlight_line(buf, line, 'Comment')
  end

  if model.header_line then
    highlight_line(buf, model.header_line - 1, 'Identifier')
  end

  if model.separator_line then
    highlight_line(buf, model.separator_line - 1, 'Comment')
  end

  for row_index, ranges in ipairs(model.cell_ranges or {}) do
    local line = model.data_start + row_index - 2
    local state_range = model.state_ranges[row_index]

    if row_is_dirty(model, row_index) and state_range then
      vim.api.nvim_buf_add_highlight(buf, namespace, 'DiffChange', line, state_range.start_col, state_range.end_col)
    end

    for column_index, range in ipairs(ranges) do
      if cell_is_dirty(model, row_index, column_index) then
        vim.api.nvim_buf_add_highlight(buf, namespace, 'DiffChange', line, range.start_col, range.end_col)
      end
    end
  end

  if model.mode ~= 'edit' or not model.focus then
    return
  end

  local focus_ranges = model.cell_ranges[model.focus.row]
  local focus_range = focus_ranges and focus_ranges[model.focus.col]
  if not focus_range then
    return
  end

  local focus_line = model.data_start + model.focus.row - 2
  vim.api.nvim_buf_add_highlight(buf, namespace, 'Visual', focus_line, focus_range.start_col, focus_range.end_col)
end

local function clamp_position(model, row_index, column_index)
  if #model.rows == 0 or #model.columns == 0 then
    return nil, nil
  end

  local row = math.min(math.max(row_index or 1, 1), #model.rows)
  local column = math.min(math.max(column_index or 1, 1), #model.columns)
  return row, column
end

local function current_cell(buf, model)
  if vim.api.nvim_get_current_buf() ~= buf then
    return nil, nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row_index = cursor[1] - model.data_start + 1
  if row_index < 1 or row_index > #model.rows then
    return nil, nil
  end

  local cursor_col = cursor[2]
  local ranges = model.cell_ranges[row_index] or {}
  if #ranges == 0 then
    return nil, nil
  end

  for column_index, range in ipairs(ranges) do
    if cursor_col < range.start_col then
      return row_index, column_index
    end
    if cursor_col >= range.start_col and cursor_col < range.end_col then
      return row_index, column_index
    end
  end

  return row_index, #ranges
end

local function jump_to_cell(buf, model, row_index, column_index)
  local row, column = clamp_position(model, row_index, column_index)
  if not row or vim.api.nvim_get_current_buf() ~= buf then
    return
  end

  local range = model.cell_ranges[row] and model.cell_ranges[row][column]
  if not range then
    return
  end

  vim.api.nvim_win_set_cursor(0, { model.data_start + row - 1, range.start_col })
end

local function rerender(buf, preferred_row, preferred_col)
  local model = models[buf]
  if not model then
    return
  end

  local row, column = clamp_position(model, preferred_row, preferred_col)
  refresh_layout(model)
  set_buffer_lines(buf, model.lines)

  if row and column then
    jump_to_cell(buf, model, row, column)
  end

  M.refresh_focus(buf)
end

local function ensure_model(buf)
  local model = models[buf]
  if model then
    return model
  end

  notify.warn('No result grid is active yet.')
  return nil
end

local function ensure_edit_mode(buf)
  local model = ensure_model(buf)
  if not model then
    return nil
  end

  if not model.local_edit_supported then
    notify.warn('This result does not have editable cells in the PoC.')
    return nil
  end

  if model.mode ~= 'edit' then
    notify.warn('Press `e` to enter editable-grid PoC mode first.')
    return nil
  end

  return model
end

function M.refresh_focus(buf)
  local model = models[buf]
  if not model then
    return
  end

  if model.mode ~= 'edit' then
    model.focus = nil
    apply_highlights(buf, model)
    return
  end

  local row_index, column_index = current_cell(buf, model)
  if row_index and column_index then
    model.focus = {
      row = row_index,
      col = column_index,
    }
  else
    model.focus = nil
  end

  apply_highlights(buf, model)
end

function M.setup_buffer(buf)
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false

  local function map(lhs, rhs, desc)
    vim.keymap.set('n', lhs, rhs, { buffer = buf, silent = true, desc = desc })
  end

  map(']p', '<Cmd>DeebeeNextPage<CR>', 'Next results page')
  map('[p', '<Cmd>DeebeePrevPage<CR>', 'Previous results page')
  map('gr', '<Cmd>DeebeeRun<CR>', 'Rerun query')
  map('e', function()
    M.toggle_edit_mode(buf)
  end, 'Toggle editable-grid PoC mode')
  map('<CR>', function()
    local model = models[buf]
    if model and model.mode == 'edit' then
      M.edit_cell(buf)
      return
    end

    M.toggle_edit_mode(buf)
  end, 'Enter edit mode or edit cell')
  map('<Tab>', function()
    M.next_cell(buf)
  end, 'Jump to next cell')
  map('<S-Tab>', function()
    M.prev_cell(buf)
  end, 'Jump to previous cell')
  map('u', function()
    M.revert_row(buf)
  end, 'Revert current row')
  map('gC', function()
    M.commit(buf)
  end, 'Commit local PoC changes')
  map('gR', function()
    M.rollback(buf)
  end, 'Rollback local PoC changes')

  local group = vim.api.nvim_create_augroup('deebee-results-grid-' .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufEnter', 'WinEnter' }, {
    group = group,
    buffer = buf,
    callback = function()
      M.refresh_focus(buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    buffer = buf,
    callback = function()
      models[buf] = nil
    end,
  })
end

function M.render(buf, result)
  local model = build_initial_model(result)
  models[buf] = model
  rerender(buf, 1, 1)
end

function M.model(buf)
  return models[buf]
end

function M.has_pending_changes(buf)
  local model = models[buf]
  if not model then
    return false
  end

  local dirty_cells = dirty_counts(model)
  return dirty_cells > 0
end

function M.toggle_edit_mode(buf)
  local model = ensure_model(buf)
  if not model then
    return
  end

  if not model.local_edit_supported then
    notify.warn('This result is read-only in the PoC because there are no tabular cells to edit.')
    return
  end

  if model.mode == 'view' and #model.rows == 0 then
    notify.warn('The current page has no rows to edit in the PoC.')
    return
  end

  model.mode = model.mode == 'edit' and 'view' or 'edit'
  rerender(buf, model.focus and model.focus.row or 1, model.focus and model.focus.col or 1)

  if model.mode == 'edit' then
    notify.info('Editable-grid PoC is active. Changes stay local until you commit.')
  end
end

function M.edit_cell(buf)
  local model = ensure_edit_mode(buf)
  if not model then
    return
  end

  local row_index, column_index = current_cell(buf, model)
  if not row_index or not column_index then
    notify.warn('Move the cursor onto a table cell first.')
    return
  end

  local column_name = model.columns[column_index]
  local current_value = model.rows[row_index][column_index]

  vim.ui.input({
    prompt = string.format('%s (type NULL for null): ', column_name),
    default = display_value_for_input(current_value),
  }, function(input)
    if input == nil then
      return
    end

    model.rows[row_index][column_index] = normalize_input_value(input)
    rerender(buf, row_index, column_index)
  end)
end

function M.commit(buf)
  local model = ensure_model(buf)
  if not model then
    return
  end

  local dirty_cells, dirty_rows = dirty_counts(model)
  if dirty_cells == 0 then
    notify.info('No staged editable-grid PoC changes to commit.')
    return
  end

  model.baseline_rows = clone_rows(model.rows)
  rerender(buf, model.focus and model.focus.row or 1, model.focus and model.focus.col or 1)
  notify.info(string.format(
    'Committed %d local PoC cell changes across %d rows. No database write happened.',
    dirty_cells,
    dirty_rows
  ))
end

function M.rollback(buf)
  local model = ensure_model(buf)
  if not model then
    return
  end

  local dirty_cells = dirty_counts(model)
  if dirty_cells == 0 then
    notify.info('No staged editable-grid PoC changes to roll back.')
    return
  end

  model.rows = clone_rows(model.baseline_rows)
  rerender(buf, model.focus and model.focus.row or 1, model.focus and model.focus.col or 1)
  notify.info('Rolled back local editable-grid PoC changes.')
end

function M.revert_row(buf)
  local model = ensure_model(buf)
  if not model then
    return
  end

  local row_index, column_index = current_cell(buf, model)
  if not row_index then
    notify.warn('Move the cursor onto a data row first.')
    return
  end

  if not row_is_dirty(model, row_index) then
    notify.info('Current row has no staged PoC changes.')
    return
  end

  model.rows[row_index] = vim.deepcopy(model.baseline_rows[row_index])
  rerender(buf, row_index, column_index or 1)
end

function M.next_cell(buf)
  local model = ensure_edit_mode(buf)
  if not model then
    return
  end

  local row_index, column_index = current_cell(buf, model)
  local row = row_index or 1
  local column = column_index or 1

  if column < #model.columns then
    column = column + 1
  elseif row < #model.rows then
    row = row + 1
    column = 1
  end

  jump_to_cell(buf, model, row, column)
  M.refresh_focus(buf)
end

function M.prev_cell(buf)
  local model = ensure_edit_mode(buf)
  if not model then
    return
  end

  local row_index, column_index = current_cell(buf, model)
  local row = row_index or 1
  local column = column_index or 1

  if column > 1 then
    column = column - 1
  elseif row > 1 then
    row = row - 1
    column = #model.columns
  end

  jump_to_cell(buf, model, row, column)
  M.refresh_focus(buf)
end

return M
