if vim.g.loaded_deebee then
  return
end

vim.g.loaded_deebee = 1

require('deebee').setup()
