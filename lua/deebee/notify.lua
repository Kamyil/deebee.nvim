local M = {}

function M.info(message)
  vim.notify(message, vim.log.levels.INFO, { title = 'deebee.nvim' })
end

function M.warn(message)
  vim.notify(message, vim.log.levels.WARN, { title = 'deebee.nvim' })
end

function M.error(message)
  vim.notify(message, vim.log.levels.ERROR, { title = 'deebee.nvim' })
end

return M
