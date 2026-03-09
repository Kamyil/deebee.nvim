local config = require('deebee.config')
local constants = require('deebee.constants')
local installer = require('deebee.installer')
local rpc = require('deebee.rpc')

local M = {}

local state = {
  worker_path = nil,
  handshake = nil,
}

function M.ensure_running()
  if rpc.is_running() and state.handshake then
    return state.handshake
  end

  local worker_path = installer.install()
  rpc.start(worker_path)

  local handshake = rpc.request_sync('handshake', {
    plugin_version = constants.plugin_version,
    expected_worker_version = config.values.worker_version,
    protocol_version = config.values.protocol_version,
  }, 5000)

  state.worker_path = worker_path
  state.handshake = handshake

  return handshake
end

function M.health()
  M.ensure_running()
  return rpc.request_sync('health', {}, 5000)
end

function M.connect(connection)
  M.ensure_running()
  return rpc.request_sync('connect', {
    connection = connection,
  }, 10000)
end

function M.disconnect(session_id)
  M.ensure_running()
  return rpc.request_sync('disconnect', {
    session_id = session_id,
  }, 5000)
end

function M.list_catalog(session_id, node_kind, node_path)
  M.ensure_running()
  return rpc.request_sync('list_catalog', {
    session_id = session_id,
    node_kind = node_kind,
    node_path = node_path or {},
  }, 10000)
end

function M.run_query(session_id, sql, page_size)
  M.ensure_running()
  return rpc.request_sync('run_query', {
    session_id = session_id,
    sql = sql,
    page_size = page_size,
  }, 60000)
end

function M.fetch_page(query_id, page_index)
  M.ensure_running()
  return rpc.request_sync('fetch_page', {
    query_id = query_id,
    page_index = page_index,
  }, 10000)
end

function M.info()
  local managed_path, source = installer.resolve_worker_path()
  return {
    source = source,
    worker_path = state.worker_path or managed_path,
    expected_worker_version = config.values.worker_version,
    protocol_version = config.values.protocol_version,
    handshake = state.handshake,
  }
end

function M.stop()
  rpc.stop()
  state.handshake = nil
end

return M
