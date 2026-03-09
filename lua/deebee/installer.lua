local config = require('deebee.config')
local constants = require('deebee.constants')
local notify = require('deebee.notify')
local util = require('deebee.util')

local M = {}

local function system(command, opts)
  local result = vim.system(command, opts or { text = true }):wait()
  if result.code ~= 0 then
    error((result.stderr ~= '' and result.stderr) or (result.stdout ~= '' and result.stdout) or table.concat(command, ' '))
  end
  return result
end

local function ensure_tool(executable)
  if vim.fn.executable(executable) ~= 1 then
    error(string.format('Required executable `%s` not found in PATH.', executable))
  end
end

local function download(url, output)
  ensure_tool('curl')
  system({ 'curl', '-fL', '--retry', '2', '-o', output, url }, { text = true, timeout = config.values.download_timeout_ms })
end

local function checksum_command(path)
  if util.is_windows() then
    return {
      'powershell',
      '-NoProfile',
      '-Command',
      string.format("(Get-FileHash -Algorithm SHA256 '%s').Hash.ToLower()", path),
    }
  end

  if vim.fn.executable('shasum') == 1 then
    return { 'shasum', '-a', '256', path }
  end

  if vim.fn.executable('sha256sum') == 1 then
    return { 'sha256sum', path }
  end

  error('No SHA256 tool found. Expected `shasum`, `sha256sum`, or PowerShell.')
end

local function file_sha256(path)
  local result = system(checksum_command(path), { text = true })
  local hash = result.stdout:match('^([A-Fa-f0-9]+)')
  if not hash then
    error('Failed to read SHA256 for ' .. path)
  end
  return string.lower(hash)
end

local function expected_checksum(checksums_path, asset_name)
  for line in io.lines(checksums_path) do
    local hash, name = line:match('^([A-Fa-f0-9]+)%s+[* ]?(.-)%s*$')
    if hash and name == asset_name then
      return string.lower(hash)
    end
  end

  error('Checksum for asset `' .. asset_name .. '` not found in checksums.txt')
end

local function unpack_archive(archive_path, destination)
  vim.fn.mkdir(destination, 'p')

  if archive_path:sub(-4) == '.zip' then
    if util.is_windows() then
      system({
        'powershell',
        '-NoProfile',
        '-Command',
        string.format("Expand-Archive -LiteralPath '%s' -DestinationPath '%s' -Force", archive_path, destination),
      }, { text = true })
      return
    end

    ensure_tool('unzip')
    system({ 'unzip', '-o', archive_path, '-d', destination }, { text = true })
    return
  end

  ensure_tool('tar')
  system({ 'tar', '-xzf', archive_path, '-C', destination }, { text = true })
end

local function mark_executable(path)
  if util.is_windows() then
    return
  end

  system({ 'chmod', '+x', path }, { text = true })
end

function M.resolve_worker_path()
  local override = vim.g.deebee_worker_path or config.values.worker_path
  if override and override ~= '' then
    return vim.fn.expand(override), 'override'
  end

  local target = util.target_triple()
  return util.installed_worker_path(config.values.worker_version, target), 'managed'
end

function M.is_installed()
  local path = M.resolve_worker_path()
  return util.executable(path)
end

function M.install(opts)
  opts = opts or {}

  local override = vim.g.deebee_worker_path or config.values.worker_path
  if override and override ~= '' then
    return vim.fn.expand(override)
  end

  local version = config.values.worker_version
  local repo = config.values.github_repo
  local target = util.target_triple()
  local asset_name = util.asset_name(version, target)
  local install_dir = util.install_dir(version, target)
  local worker_path = util.installed_worker_path(version, target)

  if opts.force and vim.uv.fs_unlink(worker_path) then
  end

  if util.executable(worker_path) then
    return worker_path
  end

  local temp_dir = vim.fn.tempname()
  vim.fn.mkdir(temp_dir, 'p')

  local archive_path = util.join_paths(temp_dir, asset_name)
  local checksums_path = util.join_paths(temp_dir, util.checksums_asset_name())

  notify.info(string.format('Installing %s %s for %s', constants.worker_name, version, target))

  download(util.release_url(repo, version, asset_name), archive_path)
  download(util.release_url(repo, version, util.checksums_asset_name()), checksums_path)

  local actual = file_sha256(archive_path)
  local expected = expected_checksum(checksums_path, asset_name)

  if actual ~= expected then
    error(string.format('Checksum mismatch for %s. Expected %s, got %s.', asset_name, expected, actual))
  end

  unpack_archive(archive_path, install_dir)
  mark_executable(worker_path)

  if not util.executable(worker_path) then
    error('Worker binary was not found after extraction: ' .. worker_path)
  end

  return worker_path
end

return M
