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

---Write sketch.yaml content with current config
---@param yaml_file string
---@param board string
---@param port string
---@param baudrate string|number
local function write_sketch_yaml(yaml_file, board, port, baudrate)
  local file = io.open(yaml_file, 'w')
  if file then
    file:write('default_fqbn: ' .. board .. '\n')
    file:write('default_port: ' .. port .. '\n')
    file:write('port_config:\n')
    file:write('  baudrate: ' .. tostring(baudrate) .. '\n')
    file:close()
  end
end

---Create or update sketch.yaml to match current board/port/baudrate config
---@param board string
---@param port string
function M._ensure_sketch_yaml(board, port)
  local yaml_file = 'sketch.yaml'
  local ino_files = vim.fn.glob('*.ino', false, true)
  if #ino_files == 0 then
    return
  end

  local ino = require('Arduino-Nvim')
  local baudrate = ino.baudrate

  if vim.fn.filereadable(yaml_file) == 0 then
    write_sketch_yaml(yaml_file, board, port, baudrate)
    return
  end

  -- Simple flat parse for top-level and one-level nested keys
  local current = {}
  local section = nil
  for line in io.lines(yaml_file) do
    local nested_key, nested_val = line:match('^%s+(%S+):%s*(%S+)')
    local top_key, top_val = line:match('^(%S+):%s*(%S+)')
    local section_key = line:match('^(%S+):$') or line:match('^(%S+):%s*$')
    if nested_key and nested_val and section then
      current[section .. '.' .. nested_key] = nested_val
    elseif section_key then
      section = section_key
    elseif top_key and top_val then
      current[top_key] = top_val
      section = nil
    end
  end

  if
    current['default_fqbn'] ~= board
    or current['default_port'] ~= port
    or current['port_config.baudrate'] ~= tostring(baudrate)
  then
    write_sketch_yaml(yaml_file, board, port, baudrate)
  end
end

return M
