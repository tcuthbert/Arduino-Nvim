local M = {}

function M.check()
  vim.health.start('Arduino-Nvim')

  local cli = vim.fn.exepath('arduino-cli')
  if cli ~= '' then
    vim.health.ok('arduino-cli found: ' .. cli)
  else
    vim.health.error('arduino-cli not found', {
      'Install from https://arduino.github.io/arduino-cli/',
    })
  end

  local als = vim.fn.exepath('arduino-language-server')
  if als ~= '' then
    vim.health.ok('arduino-language-server found: ' .. als)
  else
    vim.health.warn('arduino-language-server not found', {
      'Install from https://github.com/arduino/arduino-language-server',
      'Required for LSP features',
    })
  end

  local clangd = vim.fn.exepath('clangd')
  if clangd ~= '' then
    vim.health.ok('clangd found: ' .. clangd)
  else
    vim.health.warn('clangd not found', {
      'Required by arduino-language-server',
    })
  end

  local has_telescope = pcall(require, 'telescope')
  if has_telescope then
    vim.health.ok('telescope.nvim available')
  else
    vim.health.info('telescope.nvim not found (vim.ui.select used as fallback)')
  end

  local has_lspconfig = pcall(require, 'lspconfig')
  if has_lspconfig then
    vim.health.ok('nvim-lspconfig available')
  else
    vim.health.warn('nvim-lspconfig not found', {
      'Required for Arduino LSP support',
    })
  end
end

return M
