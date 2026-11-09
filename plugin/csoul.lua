if vim.g.loaded_csoul then
  return
end
vim.g.loaded_csoul = true

vim.api.nvim_create_user_command("Csoul", function()
  require("csoul").open()
end, { desc = "Open the csoul colorscheme picker" })
