---@brief [[
--- neo-slack.nvim UI キーマップモジュール
--- キーマッピングの設定を担当します
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_utils() return dependency.get('utils') end
local function get_layout() return dependency.get('ui.layout') end

---@class NeoSlackUIKeymaps
local M = {}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
local function notify(message, level, opts)
  opts = opts or {}
  opts.prefix = 'UI Keymaps: '
  get_utils().notify(message, level, opts)
end

-- キーマッピングを設定
function M.setup_keymaps()
  notify('キーマッピングを設定します', vim.log.levels.INFO)

  -- チャンネル一覧のキーマッピング
  M.setup_channels_keymaps()

  -- メッセージ一覧のキーマッピング
  M.setup_messages_keymaps()

  -- スレッド表示のキーマッピング
  M.setup_thread_keymaps()
end

-- チャンネル一覧のキーマッピングを設定
function M.setup_channels_keymaps()
  local layout = get_layout()
  if not layout.layout.channels_buf or not vim.api.nvim_buf_is_valid(layout.layout.channels_buf) then
    return
  end

  local opts = { noremap = true, silent = true }

  -- Enter: チャンネルを選択
  vim.api.nvim_buf_set_keymap(layout.layout.channels_buf, 'n', '<CR>', [[<cmd>lua require('neo-slack.ui.channels').select_channel()<CR>]], opts)

  -- r: チャンネル一覧を更新
  vim.api.nvim_buf_set_keymap(layout.layout.channels_buf, 'n', 'r', [[<cmd>lua require('neo-slack.ui.channels').refresh_channels()<CR>]], opts)

  -- q: UIを閉じる
  vim.api.nvim_buf_set_keymap(layout.layout.channels_buf, 'n', 'q', [[<cmd>lua require('neo-slack.ui.layout').close()<CR>]], opts)

  -- s: チャンネルをスター付き/解除
  vim.api.nvim_buf_set_keymap(layout.layout.channels_buf, 'n', 's', [[<cmd>lua require('neo-slack.ui.channels').toggle_star_channel()<CR>]], opts)

  -- c: セクションの折りたたみ/展開
  vim.api.nvim_buf_set_keymap(layout.layout.channels_buf, 'n', 'c', [[<cmd>lua require('neo-slack.ui.channels').toggle_section()<CR>]], opts)
end

-- メッセージ一覧のキーマッピングを設定
function M.setup_messages_keymaps()
  local layout = get_layout()
  if not layout.layout.messages_buf or not vim.api.nvim_buf_is_valid(layout.layout.messages_buf) then
    return
  end

  local opts = { noremap = true, silent = true }

  -- Enter: スレッドを表示
  vim.api.nvim_buf_set_keymap(layout.layout.messages_buf, 'n', '<CR>', [[<cmd>lua require('neo-slack.ui.messages').show_thread()<CR>]], opts)

  -- r: メッセージ一覧を更新
  vim.api.nvim_buf_set_keymap(layout.layout.messages_buf, 'n', 'r', [[<cmd>lua require('neo-slack.ui.messages').refresh_messages()<CR>]], opts)

  -- m: 新しいメッセージを送信
  vim.api.nvim_buf_set_keymap(layout.layout.messages_buf, 'n', 'm', [[<cmd>lua require('neo-slack.ui.messages').send_message()<CR>]], opts)

  -- a: リアクションを追加
  vim.api.nvim_buf_set_keymap(layout.layout.messages_buf, 'n', 'a', [[<cmd>lua require('neo-slack.ui.messages').add_reaction()<CR>]], opts)

  -- q: UIを閉じる
  vim.api.nvim_buf_set_keymap(layout.layout.messages_buf, 'n', 'q', [[<cmd>lua require('neo-slack.ui.layout').close()<CR>]], opts)
end

-- スレッド表示のキーマッピングを設定
function M.setup_thread_keymaps()
  local layout = get_layout()
  if not layout.layout.thread_buf or not vim.api.nvim_buf_is_valid(layout.layout.thread_buf) then
    return
  end

  local opts = { noremap = true, silent = true }

  -- r: スレッドを更新
  vim.api.nvim_buf_set_keymap(layout.layout.thread_buf, 'n', 'r', [[<cmd>lua require('neo-slack.ui.thread').refresh_thread()<CR>]], opts)

  -- m: スレッドに返信
  vim.api.nvim_buf_set_keymap(layout.layout.thread_buf, 'n', 'm', [[<cmd>lua require('neo-slack.ui.thread').reply_to_thread()<CR>]], opts)

  -- a: リアクションを追加
  vim.api.nvim_buf_set_keymap(layout.layout.thread_buf, 'n', 'a', [[<cmd>lua require('neo-slack.ui.thread').add_reaction_to_thread()<CR>]], opts)

  -- q: スレッド表示を閉じる
  vim.api.nvim_buf_set_keymap(layout.layout.thread_buf, 'n', 'q', [[<cmd>lua require('neo-slack.ui.thread').close_thread()<CR>]], opts)
end

return M