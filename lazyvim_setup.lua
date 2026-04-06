-- Example LazyVim plugin spec for Arduino-Nvim
return {
  'yuukiflow/Arduino-Nvim',
  dependencies = {
    'folke/snacks.nvim', -- optional, falls back to native vim.api + vim.ui.select
    'neovim/nvim-lspconfig',
  },
  ft = 'arduino',
  config = function()
    -- Optional: override defaults before any command runs
    -- require('Arduino-Nvim').setup({
    --   board = 'arduino:avr:uno',
    --   port = '/dev/ttyUSB0',
    --   baudrate = 115200,
    --   monitor_mode = 'split', -- 'split' (default) or 'float'
    -- })

    require('Arduino-Nvim.lsp').setup()
  end,
  keys = {
    { '<Leader>au', '<Plug>(ArduinoUpload)', desc = 'Arduino Upload' },
    { '<Leader>ac', '<Plug>(ArduinoCheck)', desc = 'Arduino Check' },
    { '<Leader>as', '<Plug>(ArduinoStatus)', desc = 'Arduino Status' },
    { '<Leader>ag', '<Plug>(ArduinoGUI)', desc = 'Arduino GUI' },
    { '<Leader>am', '<Plug>(ArduinoMonitor)', desc = 'Arduino Monitor' },
    { '<Leader>al', '<Plug>(ArduinoLib)', desc = 'Arduino Libraries' },
    { '<Leader>ab', '<Plug>(ArduinoSelectBoard)', desc = 'Arduino Select Board' },
    { '<Leader>ap', '<Plug>(ArduinoSelectPort)', desc = 'Arduino Select Port' },
  },
}
