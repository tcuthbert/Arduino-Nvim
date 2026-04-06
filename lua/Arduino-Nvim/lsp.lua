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
  local board = ino.board
  local clangd_path = vim.fn.exepath('clangd') or '/usr/bin/clangd'
  local arduino_cli_config = vim.fn.expand('$HOME/.arduino15/arduino-cli.yaml')

  M._ensure_sketch_yaml(board, ino.port)

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
      board,
    },
    filetypes = { 'arduino', 'cpp' },
    root_dir = function()
      return vim.fn.getcwd()
    end,
  })
end

---Create or update sketch.yaml to match current board/port config
---@param board string
---@param port string
function M._ensure_sketch_yaml(board, port)
  local yaml_file = 'sketch.yaml'
  local ino_files = vim.fn.glob('*.ino', false, true)
  if #ino_files == 0 then
    return
  end

  if vim.fn.filereadable(yaml_file) == 0 then
    local file = io.open(yaml_file, 'w')
    if file then
      file:write('default_fqbn: ' .. board .. '\n')
      file:write('default_port: ' .. port .. '\n')
      file:close()
    end
    return
  end

  local current = {}
  for line in io.lines(yaml_file) do
    local key, value = line:match('(%S+):%s*(%S+)')
    if key and value then
      current[key] = value
    end
  end

  if current['default_fqbn'] ~= board or current['default_port'] ~= port then
    local file = io.open(yaml_file, 'w')
    if file then
      file:write('default_fqbn: ' .. board .. '\n')
      file:write('default_port: ' .. port .. '\n')
      file:close()
    end
  end
end

return M
