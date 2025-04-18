---@brief [[
--- neo-slack.nvim UI レイアウトモジュール
--- UIのレイアウト管理、バッファとウィンドウの作成を担当します
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_utils() return dependency.get('utils') end

---@class NeoSlackUILayout
---@field layout table レイアウト情報
local M = {}

-- レイアウト情報
M.layout = {
  channels_win = nil,
  messages_win = nil,
  thread_win = nil,
  channels_buf = nil,
  messages_buf = nil,
  thread_buf = nil,
  channels_width = 30,
  messages_width = 70,
  thread_width = 50,
  min_width = 120,
  min_height = 30,
}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
local function notify(message, level, opts)
  opts = opts or {}
  opts.prefix = 'UI Layout: '
  get_utils().notify(message, level, opts)
end

-- バッファを作成
---@param name string バッファ名
---@param filetype string|nil ファイルタイプ
---@param modifiable boolean|nil 編集可能かどうか
---@return number バッファID
function M.create_buffer(name, filetype, modifiable)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)

  if filetype then
    vim.api.nvim_buf_set_option(buf, 'filetype', filetype)
  end

  vim.api.nvim_buf_set_option(buf, 'modifiable', modifiable or false)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'hide')
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)

  return buf
end

-- ウィンドウを作成
---@param buf number バッファID
---@param width number 幅
---@param height number 高さ
---@param row number 行位置
---@param col number 列位置
---@param border string|nil ボーダータイプ
---@param title string|nil タイトル
---@return number ウィンドウID
function M.create_window(buf, width, height, row, col, border, title)
  local win_opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = border or 'single',
    title = title,
  }

  local win = vim.api.nvim_open_win(buf, false, win_opts)
  vim.api.nvim_win_set_option(win, 'wrap', true)
  vim.api.nvim_win_set_option(win, 'cursorline', true)
  vim.api.nvim_win_set_option(win, 'winhl', 'Normal:NeoSlackNormal,FloatBorder:NeoSlackBorder')

  return win
end

-- レイアウトを計算
---@return table レイアウト情報
function M.calculate_layout()
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines - vim.o.cmdheight - 1

  -- 最小サイズをチェック
  if editor_width < M.layout.min_width or editor_height < M.layout.min_height then
    notify('エディタのサイズが小さすぎます。最小サイズ: ' .. M.layout.min_width .. 'x' .. M.layout.min_height, vim.log.levels.WARN)
    return nil
  end

  -- 各ウィンドウの幅と高さを計算
  local channels_width = M.layout.channels_width
  local messages_width = editor_width - channels_width - 4 -- ボーダーの分を引く
  local height = editor_height - 4 -- ボーダーの分を引く

  -- レイアウト情報を返す
  return {
    editor_width = editor_width,
    editor_height = editor_height,
    channels_width = channels_width,
    messages_width = messages_width,
    height = height,
  }
end

-- UIを閉じる
function M.close()
  -- ウィンドウを閉じる
  for _, win_name in ipairs({'channels_win', 'messages_win', 'thread_win'}) do
    local win = M.layout[win_name]
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
      M.layout[win_name] = nil
    end
  end

  -- バッファを削除
  for _, buf_name in ipairs({'channels_buf', 'messages_buf', 'thread_buf'}) do
    local buf = M.layout[buf_name]
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
      M.layout[buf_name] = nil
    end
  end
end

return M