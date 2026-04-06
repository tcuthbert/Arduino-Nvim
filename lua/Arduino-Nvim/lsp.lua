local M = {}

---Set up the Arduino language server using shared config from Arduino-Nvim
function M.setup()
  local has_lspconfig, lspconfig = pcall(require, 'lspconfig')
  if not has_lspconfig then
    vim.notify('nvim-lspconfig is required for Arduino LSP support.', vim.log.levels.ERROR)
    return
  end

  local als = vim.fn.exepath('arduino-language-server')
  if not als or als == '' then
    vim.notify('arduino-language-server not found in PATH.', vim.log.levels.ERROR)
    return
  end

  local ino = require('Arduino-Nvim')
  ino.save_config()

  local clangd_path = vim.fn.exepath('clangd') or '/usr/bin/clangd'
  local arduino_cli_config = vim.fn.expand('$HOME/.arduino15/arduino-cli.yaml')

  lspconfig.arduino_language_server.setup({
    cmd = {
      'arduino-language-server',
      '-cli',
      'arduino-cli',
      '-cli-config',
      arduino_cli_config,
      '-clangd',
      clangd_path,
      '-fqbn',
      ino.board,
    },
    filetypes = { 'arduino', 'cpp' },
    root_dir = function()
      return vim.fn.getcwd()
    end,
  })
end

return M
