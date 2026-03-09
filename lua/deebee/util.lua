local constants = require('deebee.constants')
local config = require('deebee.config')

local M = {}

local path_sep = package.config:sub(1, 1)

function M.join_paths(...)
  return table.concat({ ... }, path_sep)
end

function M.is_windows()
  return vim.uv.os_uname().sysname == 'Windows_NT'
end

function M.target_triple()
  local uname = vim.uv.os_uname()
  local sysname = uname.sysname
  local machine = uname.machine

  local arch_map = {
    x86_64 = 'x86_64',
    amd64 = 'x86_64',
    arm64 = 'aarch64',
    aarch64 = 'aarch64',
  }

  local arch = arch_map[string.lower(machine)]
  if not arch then
    error('Unsupported architecture: ' .. machine)
  end

  if sysname == 'Darwin' then
    return arch .. '-apple-darwin'
  end

  if sysname == 'Linux' then
    return arch .. '-unknown-linux-gnu'
  end

  if sysname == 'Windows_NT' then
    if arch ~= 'x86_64' then
      error('Unsupported Windows architecture: ' .. machine)
    end
    return arch .. '-pc-windows-msvc'
  end

  error('Unsupported operating system: ' .. sysname)
end

function M.archive_extension(target)
  if target:match('windows') then
    return '.zip'
  end

  return '.tar.gz'
end

function M.worker_binary_name()
  if M.is_windows() then
    return constants.worker_name .. '.exe'
  end

  return constants.worker_name
end

function M.install_dir(version, target)
  return M.join_paths(config.values.install_root, version, target)
end

function M.installed_worker_path(version, target)
  return M.join_paths(M.install_dir(version, target), M.worker_binary_name())
end

function M.release_tag(version)
  return 'v' .. version
end

function M.asset_name(version, target)
  return constants.worker_name .. '-' .. target .. M.archive_extension(target)
end

function M.checksums_asset_name()
  return 'checksums.txt'
end

function M.release_url(repo, version, asset_name)
  return string.format(
    'https://github.com/%s/releases/download/%s/%s',
    repo,
    M.release_tag(version),
    asset_name
  )
end

function M.executable(path)
  return vim.fn.executable(path) == 1
end

return M
