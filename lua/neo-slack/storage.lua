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
M.section_collapsed_file = M.storage_dir .. '/section_collapsed'
M.custom_sections_file = M.storage_dir .. '/custom_sections'
M.channel_section_map_file = M.storage_dir .. '/channel_section_map'

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

-- セクションの折りたたみ状態を保存
---@param section_collapsed table セクションの折りたたみ状態テーブル
---@return boolean 保存に成功したかどうか
function M.save_section_collapsed(section_collapsed)
  if not M.init() then
    return false
  end
  
  local file = io.open(M.section_collapsed_file, 'w')
  if not file then
    utils.notify('セクションの折りたたみ状態の保存に失敗しました', vim.log.levels.ERROR)
    return false
  end
  
  -- セクション名と折りたたみ状態を1行ずつ保存
  for section_name, is_collapsed in pairs(section_collapsed) do
    if is_collapsed then
      file:write(section_name .. '\n')
    end
  end
  file:close()
  
  return true
end

-- セクションの折りたたみ状態を読み込み
---@return table セクションの折りたたみ状態テーブル
function M.load_section_collapsed()
  local section_collapsed = {}
  
  if vim.fn.filereadable(M.section_collapsed_file) == 0 then
    return section_collapsed
  end
  
  local file = io.open(M.section_collapsed_file, 'r')
  if not file then
    utils.notify('セクションの折りたたみ状態ファイルの読み込みに失敗しました', vim.log.levels.ERROR)
    return section_collapsed
  end
  
  -- 1行ずつ読み込み
  for line in file:lines() do
    if line and line ~= '' then
      section_collapsed[line] = true
    end
  end
  file:close()
  
  return section_collapsed
end

-- カスタムセクションを保存
---@param custom_sections table カスタムセクションのテーブル
---@return boolean 保存に成功したかどうか
function M.save_custom_sections(custom_sections)
  if not M.init() then
    return false
  end
  
  local file = io.open(M.custom_sections_file, 'w')
  if not file then
    utils.notify('カスタムセクションの保存に失敗しました', vim.log.levels.ERROR)
    return false
  end
  
  -- JSONに変換して保存
  local json_str = vim.fn.json_encode(custom_sections)
  file:write(json_str)
  file:close()
  
  return true
end

-- カスタムセクションを読み込み
---@return table カスタムセクションのテーブル
function M.load_custom_sections()
  local custom_sections = {}
  
  if vim.fn.filereadable(M.custom_sections_file) == 0 then
    return custom_sections
  end
  
  local file = io.open(M.custom_sections_file, 'r')
  if not file then
    utils.notify('カスタムセクションファイルの読み込みに失敗しました', vim.log.levels.ERROR)
    return custom_sections
  end
  
  local content = file:read('*all')
  file:close()
  
  if content and content ~= '' then
    local ok, decoded = pcall(vim.fn.json_decode, content)
    if ok and decoded then
      custom_sections = decoded
    end
  end
  
  return custom_sections
end

-- チャンネルとセクションの関連付けを保存
---@param channel_section_map table チャンネルとセクションの関連付けテーブル
---@return boolean 保存に成功したかどうか
function M.save_channel_section_map(channel_section_map)
  if not M.init() then
    return false
  end
  
  local file = io.open(M.channel_section_map_file, 'w')
  if not file then
    utils.notify('チャンネルとセクションの関連付けの保存に失敗しました', vim.log.levels.ERROR)
    return false
  end
  
  -- JSONに変換して保存
  local json_str = vim.fn.json_encode(channel_section_map)
  file:write(json_str)
  file:close()
  
  return true
end

-- チャンネルとセクションの関連付けを読み込み
---@return table チャンネルとセクションの関連付けテーブル
function M.load_channel_section_map()
  local channel_section_map = {}
  
  if vim.fn.filereadable(M.channel_section_map_file) == 0 then
    return channel_section_map
  end
  
  local file = io.open(M.channel_section_map_file, 'r')
  if not file then
    utils.notify('チャンネルとセクションの関連付けファイルの読み込みに失敗しました', vim.log.levels.ERROR)
    return channel_section_map
  end
  
  local content = file:read('*all')
  file:close()
  
  if content and content ~= '' then
    local ok, decoded = pcall(vim.fn.json_decode, content)
    if ok and decoded then
      channel_section_map = decoded
    end
  end
  
  return channel_section_map
end

return M