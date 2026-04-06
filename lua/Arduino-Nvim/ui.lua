local M = {}

local has_snacks, Snacks = pcall(require, 'snacks')

---Strip ANSI escape codes from a string
---@param line string
---@return string
function M.strip_ansi(line)
  return line:gsub('\27%[[0-9;]*m', '')
end

---Split a string by newlines
---@param input string
---@return string[]
local function split_lines(input)
  local result = {}
  for line in input:gmatch('[^\r\n]+') do
    table.insert(result, line)
  end
  return result
end

---Adjust floating window height to fit content (native fallback)
---@param win integer
---@param buf integer
---@param opts table
local function adjust_window_height(win, buf, opts)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  local line_count = vim.api.nvim_buf_line_count(buf)
  local new_height = math.min(line_count, vim.o.lines - 2)
  opts.height = new_height
  opts.row = vim.o.lines - new_height - 2
  vim.api.nvim_win_set_config(win, opts)
end

---Create a floating output window at the bottom of the screen
---@return integer buf
---@return integer win
---@return table opts
function M.create_floating_monitor()
  if has_snacks then
    local swin = Snacks.win({
      position = 'bottom',
      height = 5,
      border = 'rounded',
      enter = true,
      bo = { buftype = 'nofile', modifiable = true },
      keys = {
        ['<CR>'] = 'close',
        q = 'close',
      },
    })
    local buf = swin.buf
    local win = swin.win
    local opts = { _snacks_win = swin }
    return buf, win, opts
  end

  -- Native fallback
  local width = vim.o.columns
  local height = 5

  local buf = vim.api.nvim_create_buf(false, true)
  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = vim.o.lines - height - 2,
    col = 0,
    style = 'minimal',
    border = 'rounded',
  }

  local win = vim.api.nvim_open_win(buf, true, opts)

  vim.keymap.set('n', '<CR>', function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, false)
    end
  end, { buffer = buf, silent = true })

  return buf, win, opts
end

---Append lines to a floating buffer, stripping ANSI codes and adjusting height
---@param lines string|string[]
---@param buf integer
---@param win integer
---@param opts table
function M.append_to_buffer(lines, buf, win, opts)
  if type(lines) == 'string' then
    lines = { lines }
  end

  local processed = {}
  for _, line in ipairs(lines) do
    vim.list_extend(processed, split_lines(line))
  end

  local cleaned = vim.tbl_map(M.strip_ansi, processed)

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, cleaned)

    if opts._snacks_win then
      -- Resize snacks window via raw handle
      if vim.api.nvim_win_is_valid(win) then
        local line_count = vim.api.nvim_buf_line_count(buf)
        local new_height = math.min(line_count, vim.o.lines - 2)
        vim.api.nvim_win_set_config(win, {
          relative = 'editor',
          width = vim.o.columns,
          height = new_height,
          row = vim.o.lines - new_height - 2,
          col = 0,
        })
      end
    else
      adjust_window_height(win, buf, opts)
    end
  end)
end

---Show a selection picker, using snacks.picker if available, otherwise vim.ui.select
---@param items any[]
---@param picker_opts {prompt: string, format_item?: fun(item: any): string}
---@param on_choice fun(item: any)
function M.pick(items, picker_opts, on_choice)
  if has_snacks and Snacks.picker then
    Snacks.picker.select(items, {
      prompt = picker_opts.prompt,
      format_item = picker_opts.format_item or tostring,
    }, function(item)
      if item then
        on_choice(item)
      end
    end)
  else
    vim.ui.select(items, {
      prompt = picker_opts.prompt,
      format_item = picker_opts.format_item or tostring,
    }, function(choice)
      if choice then
        on_choice(choice)
      end
    end)
  end
end

---Open a floating terminal, using snacks.terminal if available
---@param cmd string
---@param term_opts? {cwd?: string, on_exit?: fun(job_id: integer, code: integer)}
function M.open_terminal(cmd, term_opts)
  term_opts = term_opts or {}

  if has_snacks and Snacks.terminal then
    Snacks.terminal.open(cmd, {
      cwd = term_opts.cwd,
      win = {
        position = 'float',
        width = 0.8,
        height = 0.8,
        border = 'rounded',
      },
    })
    return
  end

  -- Native fallback
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

  vim.fn.termopen(cmd, {
    cwd = term_opts.cwd,
    on_exit = function(_, code)
      if term_opts.on_exit then
        term_opts.on_exit(_, code)
      end
      if code ~= 0 and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
          '',
          'Exited with code: ' .. code,
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

---Run a shell command asynchronously and call back with the output
---@param cmd string
---@param callback fun(output: string, code: integer)
function M.async_cmd(cmd, callback)
  local output = {}
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        output = data
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        callback(table.concat(output, '\n'), code)
      end)
    end,
  })
end

return M
