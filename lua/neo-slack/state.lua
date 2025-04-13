---@brief [[
--- neo-slack.nvim 状態管理モジュール
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
-- 循環参照を避けるため、storageモジュールは遅延読み込みする
local storage

local M = {}

-- storageモジュールを取得する関数
local function get_storage()
  if not storage then
    storage = require('neo-slack.storage')
  end
  return storage
end

-- 状態の初期化
M.current_channel_id = nil
M.current_channel_name = nil
M.current_thread_ts = nil
M.current_thread_message = nil
M.channels = {}
M.messages = {}
M.thread_messages = {}
M.starred_channels = {} -- スター付きチャンネルのIDを保存するテーブル
M.section_collapsed = {} -- セクションの折りたたみ状態を保存するテーブル
M.custom_sections = {} -- カスタムセクションのリスト
M.users_cache = {} -- ユーザー情報のキャッシュ
M.channel_section_map = {} -- チャンネルとセクションの関連付け
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

-- セクションの折りたたみ状態を設定
---@param section_name string セクション名
---@param is_collapsed boolean 折りたたみ状態
function M.set_section_collapsed(section_name, is_collapsed)
  M.section_collapsed[section_name] = is_collapsed
end

-- セクションの折りたたみ状態を取得
---@param section_name string セクション名
---@return boolean 折りたたみ状態
function M.is_section_collapsed(section_name)
  -- デフォルトでは展開状態（falseを返す）
  return M.section_collapsed[section_name] == true
end

-- セクションの折りたたみ状態を初期化
function M.init_section_collapsed()
  -- 保存された折りたたみ状態を読み込み
  local saved_collapsed = get_storage().load_section_collapsed()
  
  -- デフォルトでは「スター付き」セクションは展開、「チャンネル」セクションは展開
  M.section_collapsed = {
    starred = saved_collapsed.starred or false,  -- スター付きセクション
    channels = saved_collapsed.channels or false  -- チャンネルセクション
  }
end

-- セクションの折りたたみ状態を保存
function M.save_section_collapsed()
  get_storage().save_section_collapsed(M.section_collapsed)
end

-- スター付きチャンネルを保存
function M.save_starred_channels()
  get_storage().save_starred_channels(M.starred_channels)
end

-- カスタムセクションを保存
function M.save_custom_sections()
  get_storage().save_custom_sections(M.custom_sections)
end

-- チャンネルとセクションの関連付けを保存
function M.save_channel_section_map()
  get_storage().save_channel_section_map(M.channel_section_map)
end

-- セクションを追加
---@param name string セクション名
---@return string セクションID
function M.add_section(name)
  local id = os.time() .. '_' .. math.random(1000, 9999) -- ユニークIDを生成
  M.custom_sections[id] = {
    id = id,
    name = name,
    order = table.maxn(M.custom_sections) + 1,
    is_collapsed = false
  }
  return id
end

-- セクションを削除
---@param section_id string セクションID
function M.remove_section(section_id)
  -- セクションに属するチャンネルの関連付けを解除
  for channel_id, sec_id in pairs(M.channel_section_map) do
    if sec_id == section_id then
      M.channel_section_map[channel_id] = nil
    end
  end
  -- セクションを削除
  M.custom_sections[section_id] = nil
end

-- チャンネルをセクションに割り当て
---@param channel_id string チャンネルID
---@param section_id string|nil セクションID (nilの場合は割り当て解除)
function M.assign_channel_to_section(channel_id, section_id)
  if section_id and M.custom_sections[section_id] then
    M.channel_section_map[channel_id] = section_id
  else
    M.channel_section_map[channel_id] = nil
  end
end

-- チャンネルが属するセクションを取得
---@param channel_id string チャンネルID
---@return string|nil セクションID
function M.get_channel_section(channel_id)
  return M.channel_section_map[channel_id]
end

-- カスタムセクションを保存
function M.save_custom_sections()
  get_storage().save_custom_sections(M.custom_sections)
end

-- チャンネルとセクションの関連付けを保存
function M.save_channel_section_map()
  get_storage().save_channel_section_map(M.channel_section_map)
end

-- セクションに属するチャンネルを取得
---@param section_id string セクションID
---@return table チャンネルIDのリスト
function M.get_section_channels(section_id)
  local channels = {}
  for channel_id, sec_id in pairs(M.channel_section_map) do
    if sec_id == section_id then
      table.insert(channels, channel_id)
    end
  end
  return channels
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
  M.section_collapsed = {}
  M.custom_sections = {}
  M.channel_section_map = {}
  M.initialized = false
  M.users_cache = {}
end

-- ユーザーIDからユーザー情報を取得
---@param user_id string ユーザーID
---@return table|nil ユーザーオブジェクト
function M.get_user_by_id(user_id)
  -- キャッシュにユーザー情報があれば、それを返す
  if M.users_cache[user_id] then
    return M.users_cache[user_id]
  end
  
  -- APIモジュールを遅延読み込み（循環参照を避けるため）
  local api = require('neo-slack.api')
  
  -- 同期的に使用するためのフラグ
  local user_data = nil
  local completed = false
  
  -- APIからユーザー情報を取得（非同期）
  api.get_user_info_by_id(user_id, function(success, data)
    if success then
      -- キャッシュに保存
      M.users_cache[user_id] = data
      user_data = data
    end
    completed = true
  end)
  
  -- 非同期処理が完了するまで少し待機（最大100ms）
  local wait_count = 0
  while not completed and wait_count < 10 do
    vim.wait(10)
    wait_count = wait_count + 1
  end
  
  return user_data
end

return M