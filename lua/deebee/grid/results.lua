local M = {}

local namespace = vim.api.nvim_create_namespace('deebee-results-grid')
local models = {}

local function stringify_cell(value)
  if value == vim.NIL or value == nil then
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

local function is_numeric(value)
  return type(value) == 'number' or (type(value) == 'string' and value:match('^%-?%d+[%.%d]*$') ~= nil)
end

local function truncate(value, max_width)
  if vim.fn.strdisplaywidth(value) <= max_width then
    return value
  end

  return vim.fn.strcharpart(value, 0, max_width - 1) .. '…'
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

local function build_model(result)
  local page = result.page or result
  local columns = page.columns or result.columns or {}
  local rows = page.rows or {}
  local total_rows = result.row_count or page.total_rows or #rows
  local page_index = page.page_index or 0
  local page_size = page.page_size or #rows
  local first_row = total_rows == 0 and 0 or (page_index * page_size) + 1
  local last_row = total_rows == 0 and 0 or math.min(first_row + #rows - 1, total_rows)
  local row_number_width = math.max(3, #tostring(math.max(total_rows, #rows, 1)))
  local widths = { row_number_width }
  local align_right = { true }

  if #columns == 0 then
    local lines = {
      string.format('Query %s', result.query_id or page.query_id or '?'),
      string.format('Rows %d-%d of %d | Page %d', first_row, last_row, total_rows, page_index + 1),
    }

    if result.command_tag then
      table.insert(lines, 'Command tag: ' .. result.command_tag)
    end

    table.insert(lines, '')
    table.insert(lines, '[No tabular rows returned]')

    return {
      lines = lines,
      columns = columns,
      rows = rows,
      meta_lines = #lines - 1,
      header_line = nil,
      separator_line = nil,
      data_start = #lines,
    }
  end

  for index, column in ipairs(columns) do
    widths[index + 1] = math.min(math.max(vim.fn.strdisplaywidth(column), 6), 32)
    align_right[index + 1] = false
  end

  for _, row in ipairs(rows) do
    for index, value in ipairs(row) do
      local text = stringify_cell(value)
      widths[index + 1] = math.min(math.max(widths[index + 1] or 6, vim.fn.strdisplaywidth(text)), 32)
      if is_numeric(value) then
        align_right[index + 1] = true
      end
    end
  end

  local function format_row(row_index, row)
    local cells = {
      pad(tostring(row_index), widths[1], true),
    }

    for index = 1, #columns do
      local text = truncate(stringify_cell(row[index]), widths[index + 1])
      table.insert(cells, pad(text, widths[index + 1], align_right[index + 1]))
    end

    return '| ' .. table.concat(cells, ' | ') .. ' |'
  end

  local separator_cells = {}
  for _, width in ipairs(widths) do
    table.insert(separator_cells, string.rep('-', width))
  end

  local header_cells = {
    pad('#', widths[1], true),
  }

  for index, column in ipairs(columns) do
    table.insert(header_cells, pad(column, widths[index + 1], false))
  end

  local lines = {
    string.format('Query %s', result.query_id or page.query_id or '?'),
    string.format(
      'Rows %d-%d of %d | Page %d | Page size %d%s',
      first_row,
      last_row,
      total_rows,
      page_index + 1,
      page_size,
      page.has_more and ' | More rows available' or ''
    ),
  }

  if result.command_tag then
    table.insert(lines, 'Command tag: ' .. result.command_tag)
  end

  table.insert(lines, '')
  table.insert(lines, '| ' .. table.concat(header_cells, ' | ') .. ' |')
  table.insert(lines, '|-' .. table.concat(separator_cells, '-|-') .. '-|')

  local data_start = #lines

  if #rows == 0 then
    table.insert(lines, '| ' .. pad('0', widths[1], true) .. ' | ' .. pad('[no rows]', math.max(9, widths[2] or 9), false) .. ' |')
  else
    for index, row in ipairs(rows) do
      table.insert(lines, format_row(first_row + index - 1, row))
    end
  end

  return {
    lines = lines,
    columns = columns,
    rows = rows,
    meta_lines = 3,
    header_line = #lines > 0 and 4 or 1,
    separator_line = #lines > 0 and 5 or 1,
    data_start = data_start + 1,
  }
end

local function apply_highlights(buf, model)
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  highlight_line(buf, 0, 'Title')
  highlight_line(buf, 1, 'Comment')

  local command_tag_line = vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1]
  if command_tag_line and command_tag_line ~= '' then
    highlight_line(buf, 2, 'Comment')
  end

  if model.header_line then
    highlight_line(buf, model.header_line - 1, 'Identifier')
  end

  if model.separator_line then
    highlight_line(buf, model.separator_line - 1, 'Comment')
  end
end

function M.setup_buffer(buf)
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = false
  vim.bo[buf].buflisted = false
  vim.bo[buf].swapfile = false

  vim.keymap.set('n', ']p', '<Cmd>DeebeeNextPage<CR>', { buffer = buf, silent = true, desc = 'Next results page' })
  vim.keymap.set('n', '[p', '<Cmd>DeebeePrevPage<CR>', { buffer = buf, silent = true, desc = 'Previous results page' })
  vim.keymap.set('n', 'gr', '<Cmd>DeebeeRun<CR>', { buffer = buf, silent = true, desc = 'Rerun query' })
end

function M.render(buf, result)
  local model = build_model(result)
  models[buf] = model
  set_buffer_lines(buf, model.lines)
  apply_highlights(buf, model)
end

function M.model(buf)
  return models[buf]
end

return M
