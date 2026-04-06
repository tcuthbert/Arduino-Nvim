if vim.g.loaded_arduino_nvim then
  return
end
vim.g.loaded_arduino_nvim = true

-- <Plug> mappings — users bind these in their own config
vim.keymap.set('n', '<Plug>(ArduinoUpload)', function()
  require('Arduino-Nvim').upload()
end)
vim.keymap.set('n', '<Plug>(ArduinoCheck)', function()
  require('Arduino-Nvim').check()
end)
vim.keymap.set('n', '<Plug>(ArduinoStatus)', function()
  require('Arduino-Nvim').status()
end)
vim.keymap.set('n', '<Plug>(ArduinoGUI)', function()
  require('Arduino-Nvim').gui()
end)
vim.keymap.set('n', '<Plug>(ArduinoMonitor)', function()
  require('Arduino-Nvim').monitor()
end)
vim.keymap.set('n', '<Plug>(ArduinoLib)', function()
  require('Arduino-Nvim.lib').library_manager()
end)
vim.keymap.set('n', '<Plug>(ArduinoSelectBoard)', function()
  require('Arduino-Nvim').select_board()
end)
vim.keymap.set('n', '<Plug>(ArduinoSelectPort)', function()
  require('Arduino-Nvim').select_port()
end)
vim.keymap.set('n', '<Plug>(ArduinoList)', function()
  require('Arduino-Nvim').list_ports()
end)

---@type table<string, fun(args: string[])>
local subcommands = {
  check = function()
    require('Arduino-Nvim').check()
  end,
  upload = function()
    require('Arduino-Nvim').upload()
  end,
  monitor = function()
    require('Arduino-Nvim').monitor()
  end,
  status = function()
    require('Arduino-Nvim').status()
  end,
  gui = function()
    require('Arduino-Nvim').gui()
  end,
  board = function()
    require('Arduino-Nvim').select_board()
  end,
  port = function()
    require('Arduino-Nvim').select_port()
  end,
  list = function()
    require('Arduino-Nvim').list_ports()
  end,
  lib = function()
    require('Arduino-Nvim.lib').library_manager()
  end,
  baud = function(args)
    if not args[1] or args[1] == '' then
      vim.notify('Usage: :Ino baud <rate>', vim.log.levels.WARN)
      return
    end
    require('Arduino-Nvim').set_baudrate(args[1])
  end,
  lsp = function()
    require('Arduino-Nvim.lsp').setup()
  end,
}

vim.api.nvim_create_user_command('Ino', function(opts)
  local args = opts.fargs
  local subcmd = args[1]
  if not subcmd or not subcommands[subcmd] then
    local available = vim.tbl_keys(subcommands)
    table.sort(available)
    vim.notify('Usage: :Ino <' .. table.concat(available, '|') .. '>', vim.log.levels.WARN)
    return
  end
  subcommands[subcmd]({ unpack(args, 2) })
end, {
  nargs = '+',
  complete = function(_, line)
    local parts = vim.split(vim.trim(line), '%s+')
    if #parts <= 2 then
      local prefix = parts[2] or ''
      return vim.tbl_filter(function(key)
        return key:find(prefix, 1, true) == 1
      end, vim.tbl_keys(subcommands))
    end
    return {}
  end,
})
