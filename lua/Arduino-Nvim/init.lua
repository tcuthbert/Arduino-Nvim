---@class ArduinoNvim
local M = {}

local SKETCH_YAML = 'sketch.yaml'

---@class ArduinoNvimConfig
local defaults = {
  board = 'arduino:avr:uno',
  port = '/dev/ttyUSB0',
  baudrate = 115200,
  monitor_mode = 'split', -- 'split' or 'float'
}

M.board = defaults.board
M.port = defaults.port
M.baudrate = defaults.baudrate
M.monitor_mode = defaults.monitor_mode

local loaded = false

---@param s string
---@return string
local function trim(s)
  return s:match('^%s*(.-)%s*$')
end

---Parse sketch.yaml into a flat key table (supports one level of nesting)
---@param path string
---@return table<string, string>
local function parse_sketch_yaml(path)
  local values = {}
  local section = nil
  for line in io.lines(path) do
    local nested_key, nested_val = line:match('^%s+(%S+):%s*(%S+)')
    local top_key, top_val = line:match('^(%S+):%s*(%S+)')
    local section_key = line:match('^(%S+):%s*$')
    if nested_key and nested_val and section then
      values[section .. '.' .. nested_key] = nested_val
    elseif section_key then
      section = section_key
    elseif top_key and top_val then
      values[top_key] = top_val
      section = nil
    end
  end
  return values
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

---Load config from sketch.yaml, merging with current state
function M.load_config()
  if vim.fn.filereadable(SKETCH_YAML) == 0 then
    return
  end

  local values = parse_sketch_yaml(SKETCH_YAML)
  M.board = values['default_fqbn'] or M.board
  M.port = values['default_port'] or M.port
  M.baudrate = values['port_config.baudrate'] or M.baudrate
end

---Save current config to sketch.yaml
function M.save_config()
  local file = io.open(SKETCH_YAML, 'w')
  if not file then
    vim.notify('Cannot write to ' .. SKETCH_YAML, vim.log.levels.ERROR)
    return
  end
  file:write('default_fqbn: ' .. M.board .. '\n')
  file:write('default_port: ' .. M.port .. '\n')
  file:write('port_config:\n')
  file:write('  baudrate: ' .. tostring(M.baudrate) .. '\n')
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
  local buf, win, opts = ui.create_floating_monitor('Arduino Status')
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
  local buf, win, opts = ui.create_floating_monitor('Compile')
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
  local buf, win, opts = ui.create_floating_monitor('Compile & Upload')
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
  local buf, win, opts = ui.create_floating_monitor('Connected Boards')

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

  local ui = require('Arduino-Nvim.ui')
  local cmd = string.format('arduino-cli monitor -p %s -b %s', M.port, M.board)
  ui.open_terminal(cmd, {
    cwd = vim.fn.expand('%:p:h'),
    mode = M.monitor_mode,
  })
end

return M
