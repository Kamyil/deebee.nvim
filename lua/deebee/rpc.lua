local notify = require('deebee.notify')

local M = {}

local state = {
  job_id = nil,
  next_id = 1,
  pending = {},
  stdout_buffer = '',
}

local function clear_state()
  for _, callback in pairs(state.pending) do
    callback('worker process stopped unexpectedly')
  end

  state.job_id = nil
  state.next_id = 1
  state.pending = {}
  state.stdout_buffer = ''
end

local function handle_message(line)
  if line == '' then
    return
  end

  local ok, decoded = pcall(vim.json.decode, line)
  if not ok then
    notify.warn('Failed to decode worker response: ' .. line)
    return
  end

  if decoded.id == nil then
    return
  end

  local callback = state.pending[tostring(decoded.id)]
  if not callback then
    return
  end

  state.pending[tostring(decoded.id)] = nil

  if decoded.error then
    callback(decoded.error, nil)
    return
  end

  callback(nil, decoded.result)
end

local function on_stdout(_, data)
  if not data then
    return
  end

  local chunk = table.concat(data, '\n')
  if chunk == '' then
    return
  end

  state.stdout_buffer = state.stdout_buffer .. chunk

  while true do
    local newline = state.stdout_buffer:find('\n', 1, true)
    if not newline then
      break
    end

    local line = state.stdout_buffer:sub(1, newline - 1)
    state.stdout_buffer = state.stdout_buffer:sub(newline + 1)
    handle_message(line)
  end
end

local function on_stderr(_, data)
  if not data then
    return
  end

  local message = table.concat(data, '\n'):gsub('%s+$', '')
  if message ~= '' then
    notify.warn(message)
  end
end

function M.start(worker_path)
  if state.job_id and vim.fn.jobwait({ state.job_id }, 0)[1] == -1 then
    return state.job_id
  end

  state.stdout_buffer = ''
  state.job_id = vim.fn.jobstart({ worker_path, '--stdio' }, {
    on_stdout = on_stdout,
    on_stderr = on_stderr,
    on_exit = function()
      clear_state()
    end,
    stdout_buffered = false,
    stderr_buffered = false,
  })

  if state.job_id <= 0 then
    state.job_id = nil
    error('Failed to start worker process: ' .. worker_path)
  end

  return state.job_id
end

function M.stop()
  if not state.job_id then
    return
  end

  vim.fn.jobstop(state.job_id)
  clear_state()
end

function M.request(method, params, callback)
  if not state.job_id then
    callback({ message = 'worker is not running', category = 'worker_startup' }, nil)
    return
  end

  local id = state.next_id
  state.next_id = state.next_id + 1
  state.pending[tostring(id)] = callback

  local payload = vim.json.encode({ id = id, method = method, params = params or {} }) .. '\n'
  vim.fn.chansend(state.job_id, payload)
end

function M.request_sync(method, params, timeout_ms)
  local done = false
  local err
  local result

  M.request(method, params, function(callback_err, callback_result)
    err = callback_err
    result = callback_result
    done = true
  end)

  local ok = vim.wait(timeout_ms or 5000, function()
    return done
  end, 20)

  if not ok then
    error('Timed out waiting for worker response for method `' .. method .. '`.')
  end

  if err then
    error(type(err) == 'table' and (err.message or vim.inspect(err)) or tostring(err))
  end

  return result
end

function M.is_running()
  return state.job_id ~= nil and vim.fn.jobwait({ state.job_id }, 0)[1] == -1
end

return M
