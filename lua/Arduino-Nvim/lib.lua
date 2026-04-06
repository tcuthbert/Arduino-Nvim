local M = {}

local cache_file = vim.fn.stdpath('cache') .. '/arduino_libs.json'
local cache_expiration = 7 * 24 * 60 * 60

---@param callback fun(lib_data: table|nil)
local function fetch_and_cache_libraries(callback)
  local ui = require('Arduino-Nvim.ui')
  vim.notify('Fetching libraries from arduino-cli...', vim.log.levels.INFO)

  ui.async_cmd('arduino-cli lib search --format json', function(result, code)
    if code ~= 0 then
      vim.notify('Failed to fetch libraries.', vim.log.levels.ERROR)
      callback(nil)
      return
    end

    local ok, lib_data = pcall(vim.json.decode, result)
    if not ok or not lib_data then
      vim.notify('Failed to parse library JSON.', vim.log.levels.ERROR)
      callback(nil)
      return
    end

    local handle = io.open(cache_file, 'w')
    if handle then
      handle:write(vim.json.encode(lib_data))
      handle:close()
    end

    callback(lib_data)
  end)
end

---@param callback fun(lib_data: table|nil)
local function load_libraries(callback)
  local stat = vim.uv.fs_stat(cache_file)
  if stat and (os.time() - stat.mtime.sec) < cache_expiration then
    local handle = io.open(cache_file, 'r')
    if handle then
      local content = handle:read('*a')
      handle:close()
      local ok, lib_data = pcall(vim.json.decode, content)
      if ok and lib_data then
        callback(lib_data)
        return
      end
    end
  end
  fetch_and_cache_libraries(callback)
end

---@param callback fun(installed: table<string, string>)
local function get_installed_libraries(callback)
  local ui = require('Arduino-Nvim.ui')
  ui.async_cmd('arduino-cli lib list --format json', function(result)
    local ok, data = pcall(vim.json.decode, result)
    local installed = {}
    if ok and data and data.installed_libraries then
      for _, entry in ipairs(data.installed_libraries) do
        if entry.library and entry.library.name then
          installed[entry.library.name] = entry.library.version
        end
      end
    end
    callback(installed)
  end)
end

---@param callback fun(outdated: table<string, string>)
local function get_outdated_libraries(callback)
  local ui = require('Arduino-Nvim.ui')
  ui.async_cmd('arduino-cli outdated --format json', function(result)
    local ok, data = pcall(vim.json.decode, result)
    local outdated = {}
    if ok and data and data.libraries then
      for _, entry in ipairs(data.libraries) do
        local name = entry.library and entry.library.name
        local version = entry.release and entry.release.version
        if name and version then
          outdated[name] = version
        end
      end
    end
    callback(outdated)
  end)
end

function M.library_manager()
  local ino = require('Arduino-Nvim')
  if not ino.check_arduino_cli() then
    return
  end

  load_libraries(function(lib_data)
    if not lib_data or not lib_data.libraries or #lib_data.libraries == 0 then
      vim.notify('No libraries found.', vim.log.levels.WARN)
      return
    end

    get_installed_libraries(function(installed)
      get_outdated_libraries(function(outdated)
        local ui = require('Arduino-Nvim.ui')
        local entries = {}

        for _, lib in ipairs(lib_data.libraries) do
          if lib.name then
            local display = lib.name
            local tag = '[uninstalled]'

            if installed[lib.name] then
              tag = '[installed]'
              display = '✅ ' .. display
              if outdated[lib.name] then
                tag = '[outdated]'
                display = '🔄 ' .. display
              end
            end

            table.insert(entries, {
              display_name = display,
              tag = tag,
              lib_name = lib.name,
            })
          end
        end

        ui.pick(entries, {
          prompt = 'Arduino Libraries',
          format_item = function(e)
            return e.display_name
          end,
          entry_maker = function(e)
            return {
              value = e,
              display = e.display_name,
              ordinal = e.tag .. ' ' .. e.lib_name,
            }
          end,
        }, function(entry)
          local cmd = string.format('arduino-cli lib install %q', entry.lib_name)
          local action = outdated[entry.lib_name] and 'updated' or 'installed'

          ui.async_cmd(cmd, function(_, code)
            if code == 0 then
              vim.notify(
                string.format("Library '%s' %s successfully.", entry.lib_name, action),
                vim.log.levels.INFO
              )
            else
              vim.notify(
                string.format("Failed to install '%s'.", entry.lib_name),
                vim.log.levels.ERROR
              )
            end
            M.library_manager()
          end)
        end)
      end)
    end)
  end)
end

return M
