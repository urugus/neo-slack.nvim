---@brief [[
--- neo-slack 状態管理モジュール
--- プラグイン全体の状態を一元管理します
---@brief ]]

---@class NeoSlackState
---@field current_channel_id string|nil 現在選択されているチャンネルID
---@field current_channel_name string|nil 現在選択されているチャンネル名
---@field channels table[] チャンネル一覧のキャッシュ
---@field messages table チャンネルIDをキーとするメッセージのキャッシュ
---@field initialized boolean プラグインが初期化されたかどうか
local M = {}

-- 状態の初期化
M.current_channel_id = nil
M.current_channel_name = nil
M.channels = {}
M.messages = {}
M.initialized = false

-- 現在のチャンネルを設定
---@param channel_id string チャンネルID
---@param channel_name string|nil チャンネル名
function M.set_current_channel(channel_id, channel_name)
  M.current_channel_id = channel_id
  M.current_channel_name = channel_name or channel_id
end

-- 現在のチャンネルを取得
---@return string|nil channel_id チャンネルID
---@return string|nil channel_name チャンネル名
function M.get_current_channel()
  return M.current_channel_id, M.current_channel_name
end

-- チャンネル一覧を設定
---@param channels table[] チャンネルオブジェクトの配列
function M.set_channels(channels)
  M.channels = channels or {}
end

-- チャンネル一覧を取得
---@return table[] チャンネルオブジェクトの配列
function M.get_channels()
  return M.channels
end

-- チャンネルIDからチャンネル情報を取得
---@param channel_id string チャンネルID
---@return table|nil チャンネルオブジェクト
function M.get_channel_by_id(channel_id)
  for _, channel in ipairs(M.channels) do
    if channel.id == channel_id then
      return channel
    end
  end
  return nil
end

-- チャンネル名からチャンネルIDを取得
---@param channel_name string チャンネル名
---@return string|nil チャンネルID
function M.get_channel_id_by_name(channel_name)
  for _, channel in ipairs(M.channels) do
    if channel.name == channel_name then
      return channel.id
    end
  end
  return nil
end

-- メッセージを設定
---@param channel_id string チャンネルID
---@param messages table[] メッセージオブジェクトの配列
function M.set_messages(channel_id, messages)
  M.messages[channel_id] = messages or {}
end

-- メッセージを取得
---@param channel_id string チャンネルID
---@return table[] メッセージオブジェクトの配列
function M.get_messages(channel_id)
  return M.messages[channel_id] or {}
end

-- 初期化状態を設定
---@param initialized boolean 初期化されたかどうか
function M.set_initialized(initialized)
  M.initialized = initialized
end

-- 初期化状態を取得
---@return boolean 初期化されたかどうか
function M.is_initialized()
  return M.initialized
end

-- 状態をリセット
function M.reset()
  M.current_channel_id = nil
  M.current_channel_name = nil
  M.channels = {}
  M.messages = {}
  M.initialized = false
end

return M