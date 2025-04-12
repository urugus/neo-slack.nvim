---@brief [[
--- neo-slack 状態管理モジュール
--- プラグイン全体の状態を一元管理します
---@brief ]]

---@class NeoSlackState
---@field current_channel_id string|nil 現在選択されているチャンネルID
---@field current_channel_name string|nil 現在選択されているチャンネル名
---@field current_thread_ts string|nil 現在選択されているスレッドのタイムスタンプ
---@field current_thread_message table|nil 現在選択されているスレッドの親メッセージ
---@field channels table[] チャンネル一覧のキャッシュ
---@field messages table チャンネルIDをキーとするメッセージのキャッシュ
---@field thread_messages table スレッドタイムスタンプをキーとするスレッドメッセージのキャッシュ
---@field initialized boolean プラグインが初期化されたかどうか
local M = {}

-- 状態の初期化
M.current_channel_id = nil
M.current_channel_name = nil
M.current_thread_ts = nil
M.current_thread_message = nil
M.channels = {}
M.messages = {}
M.thread_messages = {}
M.starred_channels = {} -- スター付きチャンネルのIDを保存するテーブル
M.initialized = false

-- 現在のチャンネルを設定
---@param channel_id string チャンネルID
---@param channel_name string|nil チャンネル名
function M.set_current_channel(channel_id, channel_name)
  M.current_channel_id = channel_id
  M.current_channel_name = channel_name or channel_id
  -- チャンネルを変更したらスレッド情報をリセット
  M.current_thread_ts = nil
  M.current_thread_message = nil
end

-- 現在のチャンネルを取得
---@return string|nil channel_id チャンネルID
---@return string|nil channel_name チャンネル名
function M.get_current_channel()
  return M.current_channel_id, M.current_channel_name
end

-- 現在のスレッドを設定
---@param thread_ts string スレッドのタイムスタンプ
---@param thread_message table|nil スレッドの親メッセージ
function M.set_current_thread(thread_ts, thread_message)
  M.current_thread_ts = thread_ts
  M.current_thread_message = thread_message
end

-- 現在のスレッドを取得
---@return string|nil thread_ts スレッドのタイムスタンプ
---@return table|nil thread_message スレッドの親メッセージ
function M.get_current_thread()
  return M.current_thread_ts, M.current_thread_message
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

-- スレッドメッセージを設定
---@param thread_ts string スレッドのタイムスタンプ
---@param messages table[] メッセージオブジェクトの配列
function M.set_thread_messages(thread_ts, messages)
  M.thread_messages[thread_ts] = messages or {}
end

-- スレッドメッセージを取得
---@param thread_ts string スレッドのタイムスタンプ
---@return table[] メッセージオブジェクトの配列
function M.get_thread_messages(thread_ts)
  return M.thread_messages[thread_ts] or {}
end

-- タイムスタンプからメッセージを取得
---@param channel_id string チャンネルID
---@param message_ts string メッセージのタイムスタンプ
---@return table|nil メッセージオブジェクト
function M.get_message_by_ts(channel_id, message_ts)
  local messages = M.get_messages(channel_id)
  for _, message in ipairs(messages) do
    if message.ts == message_ts then
      return message
    end
  end
  return nil
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

-- スター付きチャンネルを設定
---@param channel_id string チャンネルID
---@param is_starred boolean スター付きかどうか
function M.set_channel_starred(channel_id, is_starred)
  if is_starred then
    -- スター付きに追加
    M.starred_channels[channel_id] = true
  else
    -- スター付きから削除
    M.starred_channels[channel_id] = nil
  end
end

-- チャンネルがスター付きかどうかを確認
---@param channel_id string チャンネルID
---@return boolean スター付きかどうか
function M.is_channel_starred(channel_id)
  return M.starred_channels[channel_id] == true
end

-- スター付きチャンネルのIDリストを取得
---@return table スター付きチャンネルのIDリスト
function M.get_starred_channel_ids()
  local ids = {}
  for id, _ in pairs(M.starred_channels) do
    table.insert(ids, id)
  end
  return ids
end

-- スター付きチャンネルを設定
---@param starred_channels table スター付きチャンネルのIDテーブル
function M.set_starred_channels(starred_channels)
  M.starred_channels = starred_channels or {}
end

-- 状態をリセット
function M.reset()
  M.current_channel_id = nil
  M.current_channel_name = nil
  M.current_thread_ts = nil
  M.current_thread_message = nil
  M.channels = {}
  M.messages = {}
  M.thread_messages = {}
  M.starred_channels = {}
  M.initialized = false
end

return M