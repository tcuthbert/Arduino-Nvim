local M = {}

---Strip ANSI escape codes from a string
---@param line string
---@return string
function M.strip_ansi(line)
  return line:gsub('\27%[[0-9;]*m', '')
end

---Create a floating window at the bottom of the screen
---@return integer buf
---@return integer win
---@return table opts
function M.create_floating_monitor()
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

---Adjust floating window height to fit content
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
    adjust_window_height(win, buf, opts)
  end)
end

---Show a selection picker, using Telescope if available, otherwise vim.ui.select
---@param items any[]
---@param picker_opts {prompt: string, format_item?: fun(item: any): string, ordinal?: fun(item: any): string, entry_maker?: fun(item: any): table}
---@param on_choice fun(item: any)
function M.pick(items, picker_opts, on_choice)
  local has_telescope = pcall(require, 'telescope')
  if has_telescope then
    local pickers = require('telescope.pickers')
    local finders = require('telescope.finders')
    local conf = require('telescope.config').values
    local actions = require('telescope.actions')
    local action_state = require('telescope.actions.state')

    pickers
      .new({}, {
        prompt_title = picker_opts.prompt,
        finder = finders.new_table({
          results = items,
          entry_maker = picker_opts.entry_maker or function(item)
            return {
              value = item,
              display = picker_opts.format_item and picker_opts.format_item(item) or tostring(item),
              ordinal = picker_opts.ordinal and picker_opts.ordinal(item) or tostring(item),
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr)
          actions.select_default:replace(function()
            local sel = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            if sel then
              on_choice(sel.value)
            end
          end)
          return true
        end,
      })
      :find()
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
