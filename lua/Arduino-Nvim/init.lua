---@class ArduinoNvim
local M = {}

---@class ArduinoNvimConfig
local defaults = {
  board = 'arduino:avr:uno',
  port = '/dev/ttyUSB0',
  baudrate = 115200,
  config_file = '.arduino_config.lua',
}

M.board = defaults.board
M.port = defaults.port
M.baudrate = defaults.baudrate
M.config_file = defaults.config_file

local loaded = false

---@param s string
---@return string
local function trim(s)
  return s:match('^%s*(.-)%s*$')
end

--- Ensure config is loaded on first command invocation
local function ensure_loaded()
  if not loaded then
    M.load_config()
    loaded = true
  end
end

---Optional setup for user overrides. Works without calling this.
---@param opts? ArduinoNvimConfig
function M.setup(opts)
  opts = opts or {}
  for key, default in pairs(defaults) do
    M[key] = opts[key] or default
  end
  M.load_config()
  loaded = true
end

---Load config from project-local file, merging with current state
function M.load_config()
  if vim.fn.filereadable(M.config_file) == 0 then
    return
  end

  local fn = loadfile(M.config_file)
  if fn then
    local ok, settings = pcall(fn)
    if ok and settings then
      M.board = settings.board or M.board
      M.port = settings.port or M.port
      M.baudrate = settings.baudrate or M.baudrate
    end
  end
end

---Save current config to project-local file
function M.save_config()
  local file = io.open(M.config_file, 'w')
  if not file then
    vim.notify('Cannot write to config file.', vim.log.levels.ERROR)
    return
  end
  file:write('return {\n')
  file:write(string.format('  board = %q,\n', M.board))
  file:write(string.format('  port = %q,\n', M.port))
  file:write(string.format('  baudrate = %q,\n', M.baudrate))
  file:write('}\n')
  file:close()
end

---@return boolean
function M.check_arduino_cli()
  if vim.fn.exepath('arduino-cli') == '' then
    vim.notify('arduino-cli not found in PATH.', vim.log.levels.ERROR)
    return false
  end
  return true
end

function M.set_port(port)
  ensure_loaded()
  M.port = trim(port)
  vim.notify('Port set to: ' .. M.port)
  M.save_config()
end

function M.set_board(board)
  ensure_loaded()
  M.board = trim(board)
  vim.notify('Board set to: ' .. M.board)
  M.save_config()
end

function M.set_baudrate(baudrate)
  ensure_loaded()
  M.baudrate = trim(tostring(baudrate))
  vim.notify('Baud rate set to: ' .. M.baudrate)
  M.save_config()
end

function M.status()
  ensure_loaded()
  local ui = require('Arduino-Nvim.ui')
  local buf, win, opts = ui.create_floating_monitor()
  ui.append_to_buffer({
    string.format('Board: %s', M.board),
    string.format('Port: %s', M.port),
    string.format('Baudrate: %s', M.baudrate),
  }, buf, win, opts)
end

function M.check()
  ensure_loaded()
  if not M.check_arduino_cli() then
    return
  end

  local ui = require('Arduino-Nvim.ui')
  local buf, win, opts = ui.create_floating_monitor()
  local cmd = 'arduino-cli compile --fqbn '
    .. M.board
    .. ' '
    .. vim.fn.fnameescape(vim.fn.expand('%:p:h'))

  vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      if data then
        ui.append_to_buffer(data, buf, win, opts)
      end
    end,
    on_stderr = function(_, data)
      if data then
        local errors = {}
        for _, line in ipairs(data) do
          local cleaned = ui.strip_ansi(line)
          if cleaned:match('%S') then
            table.insert(errors, 'Error: ' .. cleaned)
          end
        end
        if #errors > 0 then
          ui.append_to_buffer(errors, buf, win, opts)
        end
      end
    end,
    on_exit = function(_, code)
      local msg = code == 0 and '--- Code checked successfully. ---'
        or '--- Code check failed. ---'
      ui.append_to_buffer({ msg }, buf, win, opts)
    end,
  })
end

function M.upload()
  ensure_loaded()
  if not M.check_arduino_cli() then
    return
  end

  local ui = require('Arduino-Nvim.ui')
  local buf, win, opts = ui.create_floating_monitor()
  local dir = vim.fn.fnameescape(vim.fn.expand('%:p:h'))

  local compile_cmd = 'arduino-cli compile --fqbn ' .. M.board .. ' ' .. dir
  local upload_cmd = 'arduino-cli upload -p '
    .. M.port
    .. ' --fqbn '
    .. M.board
    .. ' --verify '
    .. dir

  local function on_stderr(_, data)
    if data and #data > 0 and data[1]:match('%S') then
      ui.append_to_buffer(
        vim.tbl_map(function(line)
          return 'Error: ' .. line
        end, data),
        buf,
        win,
        opts
      )
    end
  end

  local function start_upload()
    vim.fn.jobstart(upload_cmd, {
      stdout_buffered = false,
      on_stdout = function(_, data)
        if data then
          ui.append_to_buffer(data, buf, win, opts)
        end
      end,
      on_stderr = on_stderr,
      on_exit = function(_, code)
        if code == 0 then
          ui.append_to_buffer({ '--- Upload Complete ---' }, buf, win, opts)
        else
          ui.append_to_buffer({
            '--- Upload Failed ---',
            "Hint: Run ':Ino list' to check ports or ':Ino port' to select a different port",
          }, buf, win, opts)
        end
      end,
    })
  end

  vim.fn.jobstart(compile_cmd, {
    stdout_buffered = false,
    on_stdout = function(_, data)
      if data then
        ui.append_to_buffer(data, buf, win, opts)
      end
    end,
    on_stderr = on_stderr,
    on_exit = function(_, code)
      if code == 0 then
        ui.append_to_buffer({ '--- Compilation Complete, Starting Upload ---' }, buf, win, opts)
        start_upload()
      else
        ui.append_to_buffer({ '--- Compilation Failed ---' }, buf, win, opts)
      end
    end,
  })
end

function M.list_ports()
  ensure_loaded()
  if not M.check_arduino_cli() then
    return
  end

  local ui = require('Arduino-Nvim.ui')
  local buf, win, opts = ui.create_floating_monitor()

  vim.fn.jobstart('arduino-cli board list', {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        ui.append_to_buffer(data, buf, win, opts)
      end
    end,
    on_stderr = function(_, data)
      if data then
        ui.append_to_buffer(data, buf, win, opts)
      end
    end,
  })
end

function M.select_board(callback)
  ensure_loaded()
  if not M.check_arduino_cli() then
    return
  end

  local ui = require('Arduino-Nvim.ui')
  ui.async_cmd('arduino-cli board listall --format json', function(result, code)
    if code ~= 0 then
      vim.notify('Failed to list boards.', vim.log.levels.ERROR)
      return
    end

    local ok, parsed = pcall(vim.json.decode, result)
    if not ok or not parsed or not parsed.boards then
      vim.notify('Failed to parse board list.', vim.log.levels.ERROR)
      return
    end

    local boards = {}
    for _, b in ipairs(parsed.boards) do
      if b.fqbn then
        table.insert(boards, { name = b.name or 'Unknown', fqbn = b.fqbn })
      end
    end

    if #boards == 0 then
      vim.notify('No boards found.', vim.log.levels.WARN)
      return
    end

    ui.pick(boards, {
      prompt = 'Select Arduino Board',
      format_item = function(b)
        return b.name
      end,
      ordinal = function(b)
        return b.name
      end,
    }, function(board)
      M.set_board(board.fqbn)
      if callback then
        callback()
      end
    end)
  end)
end

function M.select_port()
  ensure_loaded()
  if not M.check_arduino_cli() then
    return
  end

  local ui = require('Arduino-Nvim.ui')
  ui.async_cmd('arduino-cli board list', function(result)
    local ports = {}
    for line in result:gmatch('[^\r\n]+') do
      if line:match('^/dev/tty') or line:match('^/dev/cu') or line:match('^COM') then
        local port = line:match('^(%S+)')
        if port then
          table.insert(ports, port)
        end
      end
    end

    if #ports == 0 then
      vim.notify('No connected ports found.', vim.log.levels.ERROR)
      return
    end

    ui.pick(ports, { prompt = 'Select Arduino Port' }, function(port)
      M.set_port(port)
    end)
  end)
end

function M.gui()
  M.select_board(function()
    M.select_port()
  end)
end

function M.monitor()
  ensure_loaded()
  if not M.check_arduino_cli() then
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local win_width = math.floor(vim.o.columns * 0.8)
  local win_height = math.floor(vim.o.lines * 0.8)
  vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = win_width,
    height = win_height,
    row = math.floor((vim.o.lines - win_height) / 2),
    col = math.floor((vim.o.columns - win_width) / 2),
    style = 'minimal',
    border = 'rounded',
  })

  local serial_cmd = string.format('arduino-cli monitor -p %s -b %s', M.port, M.board)

  vim.fn.termopen(serial_cmd, {
    cwd = vim.fn.expand('%:p:h'),
    on_exit = function(_, code)
      if code ~= 0 and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
          '',
          'Monitor exited with code: ' .. code,
        })
      end
    end,
  })

  local keymap_opts = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set('t', '<C-c>', '<C-\\><C-n>:bd!<CR>', keymap_opts)
  vim.keymap.set('n', '<C-c>', ':bd!<CR>', keymap_opts)
  vim.keymap.set('t', '<Esc>', '<C-\\><C-n>:bd!<CR>', keymap_opts)
  vim.keymap.set('n', '<Esc>', ':bd!<CR>', keymap_opts)

  vim.cmd('startinsert')
end

return M
