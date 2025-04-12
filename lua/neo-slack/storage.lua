---@brief [[
--- neo-slack ストレージモジュール
--- トークンなどの設定をローカルに保存・読み込みします
---@brief ]]

local utils = require('neo-slack.utils')

---@class NeoSlackStorage
local M = {}

-- データ保存先のパス
M.storage_dir = vim.fn.stdpath('data') .. '/neo-slack'
M.token_file = M.storage_dir .. '/token'
M.starred_channels_file = M.storage_dir .. '/starred_channels'

-- ストレージディレクトリを初期化
---@return boolean 初期化に成功したかどうか
function M.init()
  -- ディレクトリが存在しない場合は作成
  if vim.fn.isdirectory(M.storage_dir) == 0 then
    local success = vim.fn.mkdir(M.storage_dir, 'p') == 1
    if not success then
      utils.notify('ストレージディレクトリの作成に失敗しました: ' .. M.storage_dir, vim.log.levels.ERROR)
      return false
    end
  end
  return true
end

-- トークンを保存
---@param token string Slack APIトークン
---@return boolean 保存に成功したかどうか
function M.save_token(token)
  if not M.init() then
    return false
  end
  
  local file = io.open(M.token_file, 'w')
  if not file then
    utils.notify('トークンの保存に失敗しました', vim.log.levels.ERROR)
    return false
  end
  
  file:write(token)
  file:close()
  
  -- ファイルのパーミッションを600に設定（ユーザーのみ読み書き可能）
  local success = vim.loop.chmod(M.token_file, 384) -- 0600 in octal
  if not success then
    utils.notify('トークンファイルのパーミッション設定に失敗しました', vim.log.levels.WARN)
  end
  
  return true
end

-- トークンを読み込み
---@return string|nil 保存されたトークン、または存在しない場合はnil
function M.load_token()
  if vim.fn.filereadable(M.token_file) == 0 then
    return nil
  end
  
  local file = io.open(M.token_file, 'r')
  if not file then
    utils.notify('トークンファイルの読み込みに失敗しました', vim.log.levels.ERROR)
    return nil
  end
  
  local token = file:read('*all')
  file:close()
  
  -- 空文字列や空白のみの場合はnilを返す
  if not token or token:match('^%s*$') then
    return nil
  end
  
  return token
end

-- トークンを削除
---@return boolean 削除に成功したかどうか
function M.delete_token()
  if vim.fn.filereadable(M.token_file) == 1 then
    local success = vim.fn.delete(M.token_file) == 0
    if not success then
      utils.notify('トークンファイルの削除に失敗しました', vim.log.levels.ERROR)
    end
    return success
  end
  return false
end

-- スター付きチャンネルを保存
---@param starred_channels table スター付きチャンネルのIDテーブル
---@return boolean 保存に成功したかどうか
function M.save_starred_channels(starred_channels)
  if not M.init() then
    return false
  end
  
  local file = io.open(M.starred_channels_file, 'w')
  if not file then
    utils.notify('スター付きチャンネルの保存に失敗しました', vim.log.levels.ERROR)
    return false
  end
  
  -- チャンネルIDを1行ずつ保存
  for channel_id, _ in pairs(starred_channels) do
    file:write(channel_id .. '\n')
  end
  file:close()
  
  return true
end

-- スター付きチャンネルを読み込み
---@return table スター付きチャンネルのIDテーブル
function M.load_starred_channels()
  local starred_channels = {}
  
  if vim.fn.filereadable(M.starred_channels_file) == 0 then
    return starred_channels
  end
  
  local file = io.open(M.starred_channels_file, 'r')
  if not file then
    utils.notify('スター付きチャンネルファイルの読み込みに失敗しました', vim.log.levels.ERROR)
    return starred_channels
  end
  
  -- 1行ずつ読み込み
  for line in file:lines() do
    if line and line ~= '' then
      starred_channels[line] = true
    end
  end
  file:close()
  
  return starred_channels
end

return M