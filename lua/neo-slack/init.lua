---@brief [[
--- neo-slack.nvim プラグインのメインモジュール
--- プラグインの初期化と主要な機能を提供します
---@brief ]]

-- コアモジュール
local core = require('neo-slack.core')
local events = require('neo-slack.core.events')
local config = require('neo-slack.core.config')

-- 機能モジュール
local api = require('neo-slack.api')
local storage = require('neo-slack.storage')
local utils = require('neo-slack.utils')
local notification = require('neo-slack.notification')
local state = require('neo-slack.state')
local ui = require('neo-slack.ui')

---@class NeoSlack
---@field config NeoSlackConfig 設定オブジェクト
local M = {}

-- 設定をエクスポート
M.config = config.current

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
local function notify(message, level)
  utils.notify(message, level)
end

--------------------------------------------------
-- 初期化と設定関連の関数
--------------------------------------------------

--- プラグインの初期化
--- @param opts table|nil 設定オプション
--- @return boolean 初期化に成功したかどうか
function M.setup(opts)
  -- 設定の初期化
  config.setup(opts)
  
  -- トークンの取得を試みる（優先順位: 1.設定パラメータ 2.保存済みトークン 3.ユーザー入力）
  if config.get('token') == '' then
    -- ストレージからトークンを読み込み
    local saved_token = storage.load_token()
    
    if saved_token then
      config.set('token', saved_token)
      notify('保存されたトークンを読み込みました', vim.log.levels.INFO)
    else
      -- トークンの入力を求める
      notify('Slackトークンが必要です', vim.log.levels.INFO)
      M.prompt_for_token()
      return false -- プロンプト後に再度setup()が呼ばれるため、ここで終了
    end
  end
  
  -- APIクライアントの初期化
  api.setup(config.get('token'))
  
  -- 通知システムの初期化
  if config.get('notification') then
    notification.setup(config.get('refresh_interval'))
  end
  
  -- スター付きチャンネルの情報を読み込み
  local starred_channels = storage.load_starred_channels()
  state.set_starred_channels(starred_channels)
  
  -- カスタムセクションの情報を読み込み
  local custom_sections = storage.load_custom_sections()
  state.custom_sections = custom_sections
  
  -- チャンネルとセクションの関連付けを読み込み
  local channel_section_map = storage.load_channel_section_map()
  state.channel_section_map = channel_section_map
  
  -- セクションの折りたたみ状態を初期化
  state.init_section_collapsed()
  
  -- 状態を初期化済みに設定
  state.set_initialized(true)
  
  -- イベントハンドラの登録
  M.register_event_handlers()
  
  notify('初期化完了', vim.log.levels.INFO)
  
  if config.get('debug') then
    notify('デバッグモードが有効です', vim.log.levels.INFO)
  end
  
  return true
end

--- イベントハンドラを登録
function M.register_event_handlers()
  -- チャンネル選択イベント
  events.on('channel_selected', function(channel_id, channel_name)
    M.select_channel(channel_id, channel_name)
  end)
  
  -- メッセージ送信イベント
  events.on('message_sent', function(channel, text)
    M.send_message(channel, text)
  end)
  
  -- メッセージ返信イベント
  events.on('message_replied', function(message_ts, text)
    M.reply_message(message_ts, text)
  end)
  
  -- スレッド返信イベント
  events.on('thread_replied', function(thread_ts, text)
    M.reply_to_thread(thread_ts, text)
  end)
  
  -- リアクション追加イベント
  events.on('reaction_added', function(message_ts, emoji)
    M.add_reaction(message_ts, emoji)
  end)
  
  -- ファイルアップロードイベント
  events.on('file_uploaded', function(channel, file_path)
    M.upload_file(channel, file_path)
  end)
end

--- Slackの接続状態を表示
--- @return nil
function M.status()
  api.test_connection(function(success, data)
    if success then
      notify('接続成功 - ワークスペース: ' .. (data.team or 'Unknown'), vim.log.levels.INFO)
    else
      notify('接続失敗 - ' .. (data.error or 'Unknown error'), vim.log.levels.ERROR)
    end
  end)
end

--------------------------------------------------
-- トークン管理関連の関数
--------------------------------------------------

--- トークン入力を促す
--- @return nil
function M.prompt_for_token()
  vim.ui.input({
    prompt = 'Slack APIトークンを入力してください: ',
    default = '',
    completion = 'file',
    highlight = function()
      vim.api.nvim_buf_add_highlight(0, -1, 'Question', 0, 0, -1)
    end
  }, function(input)
    if not input or input == '' then
      notify('トークンが入力されませんでした。プラグインは初期化されません。', vim.log.levels.WARN)
      return
    end
    
    -- トークンの検証
    M.validate_and_save_token(input)
  end)
end

--- トークンを検証して保存
--- @param token string Slack APIトークン
--- @return nil
function M.validate_and_save_token(token)
  -- 一時的にトークンを設定してテスト
  api.setup(token)
  api.test_connection(function(success, data)
    if success then
      -- トークンを保存
      if storage.save_token(token) then
        notify('トークンを保存しました', vim.log.levels.INFO)
        
        -- 設定を更新して初期化を続行
        config.set('token', token)
        M.setup(config.get())
      else
        notify('トークンの保存に失敗しました', vim.log.levels.ERROR)
      end
    else
      notify('無効なトークンです - ' .. (data.error or 'Unknown error'), vim.log.levels.ERROR)
      -- 再度入力を促す
      vim.defer_fn(function()
        M.prompt_for_token()
      end, 1000)
    end
  end)
end

--- トークンを削除
--- @param prompt_new boolean|nil 新しいトークンの入力を促すかどうか
--- @return boolean 削除に成功したかどうか
function M.delete_token(prompt_new)
  if storage.delete_token() then
    config.set('token', '')
    notify('保存されたトークンを削除しました', vim.log.levels.INFO)
    
    -- 新しいトークンの入力を促す
    if prompt_new then
      vim.defer_fn(function()
        notify('新しいSlackトークンを入力してください', vim.log.levels.INFO)
        M.prompt_for_token()
      end, 1000)
    end
    
    return true
  end
  return false
end

--- トークンを再設定
--- @return boolean 削除に成功したかどうか
function M.reset_token()
  return M.delete_token(true)
end

--------------------------------------------------
-- チャンネル関連の関数
--------------------------------------------------

--- チャンネル一覧を取得して表示
--- @return nil
function M.list_channels()
  api.get_channels(function(success, channels)
    if success then
      -- 状態にチャンネル一覧を保存
      state.set_channels(channels)
      -- UIにチャンネル一覧を表示
      ui.show_channels(channels)
    else
      notify('チャンネル一覧の取得に失敗しました', vim.log.levels.ERROR)
    end
  end)
end

--- チャンネルを選択
--- @param channel_id string チャンネルID
--- @param channel_name string|nil チャンネル名
--- @return nil
function M.select_channel(channel_id, channel_name)
  -- 状態に現在のチャンネルを設定
  state.set_current_channel(channel_id, channel_name)
  -- チャンネルのメッセージを表示
  M.list_messages(channel_id)
end

--------------------------------------------------
-- メッセージ関連の関数
--------------------------------------------------

--- メッセージ一覧を取得して表示
--- @param channel string|nil チャンネル名またはID
--- @return nil
function M.list_messages(channel)
  -- チャンネルが指定されていない場合は、現在のチャンネルまたはデフォルトチャンネルを使用
  local channel_id, channel_name = state.get_current_channel()
  channel = channel or channel_id or config.get('default_channel')
  
  api.get_messages(channel, function(success, messages)
    if success then
      -- 状態にメッセージを保存
      if type(channel) == 'string' then
        state.set_messages(channel, messages)
      end
      -- UIにメッセージを表示
      ui.show_messages(channel, messages)
    else
      notify('メッセージの取得に失敗しました', vim.log.levels.ERROR)
    end
  end)
end

--- メッセージを送信
--- @param channel string|nil チャンネル名またはID
--- @param ... string メッセージテキスト（複数の引数は連結される）
--- @return nil
function M.send_message(channel, ...)
  -- チャンネルが指定されていない場合は、現在のチャンネルまたはデフォルトチャンネルを使用
  local channel_id = state.get_current_channel()
  channel = channel or channel_id or config.get('default_channel')
  local message = table.concat({...}, ' ')
  
  -- メッセージ送信処理
  local function do_send(text)
    api.send_message(channel, text, function(success)
      if success then
        -- メッセージ送信イベントを発行
        events.emit('message_sent_success', channel, text)
        -- 現在表示中のメッセージ一覧を更新
        M.list_messages(channel)
      else
        -- メッセージ送信失敗イベントを発行
        events.emit('message_sent_failure', channel, text)
      end
    end)
  end
  
  if message == '' then
    -- インタラクティブモードでメッセージを入力
    vim.ui.input({ prompt = 'メッセージ: ' }, function(input)
      if input and input ~= '' then
        do_send(input)
      end
    end)
  else
    do_send(message)
  end
end

--- メッセージに返信
--- @param message_ts string メッセージのタイムスタンプ
--- @param ... string 返信テキスト（複数の引数は連結される）
--- @return nil
function M.reply_message(message_ts, ...)
  local reply = table.concat({...}, ' ')
  local channel_id = state.get_current_channel()
  
  if not channel_id then
    notify('現在のチャンネルが設定されていません。メッセージ一覧を表示してから返信してください。', vim.log.levels.ERROR)
    return
  end
  
  -- 返信処理
  local function do_reply(text)
    api.reply_message(message_ts, text, function(success)
      -- 成功/失敗の通知はAPI層で行われる
      if success then
        -- 返信成功イベントを発行
        events.emit('message_replied_success', message_ts, text)
        
        -- スレッドが表示されている場合は、スレッド一覧を更新
        local current_thread_ts = state.get_current_thread()
        if current_thread_ts == message_ts then
          M.list_thread_replies(message_ts)
        else
          -- 現在表示中のメッセージ一覧を更新
          M.list_messages(channel_id)
        end
      else
        -- 返信失敗イベントを発行
        events.emit('message_replied_failure', message_ts, text)
      end
    end)
  end
  
  if reply == '' then
    -- インタラクティブモードで返信を入力
    vim.ui.input({ prompt = '返信: ' }, function(input)
      if input and input ~= '' then
        do_reply(input)
      end
    end)
  else
    do_reply(reply)
  end
end

--------------------------------------------------
-- スレッド関連の関数
--------------------------------------------------

--- スレッド返信一覧を取得して表示
--- @param thread_ts string スレッドの親メッセージのタイムスタンプ
--- @return nil
function M.list_thread_replies(thread_ts)
  local channel_id = state.get_current_channel()
  
  if not channel_id then
    notify('現在のチャンネルが設定されていません。メッセージ一覧を表示してからスレッドを表示してください。', vim.log.levels.ERROR)
    return
  end
  
  -- スレッド返信を取得
  api.get_thread_replies(channel_id, thread_ts, function(success, replies, parent_message)
    if success then
      -- 状態にスレッド情報を保存
      state.set_current_thread(thread_ts, parent_message)
      state.set_thread_messages(thread_ts, replies)
      
      -- UIにスレッド返信を表示
      ui.show_thread_replies(thread_ts, replies, parent_message)
    else
      notify('スレッド返信の取得に失敗しました', vim.log.levels.ERROR)
    end
  end)
end

--- スレッドに返信
--- @param thread_ts string スレッドの親メッセージのタイムスタンプ
--- @param ... string 返信テキスト（複数の引数は連結される）
--- @return nil
function M.reply_to_thread(thread_ts, ...)
  -- スレッドへの返信は通常の返信と同じ処理
  M.reply_message(thread_ts, ...)
end

--------------------------------------------------
-- リアクション関連の関数
--------------------------------------------------

--- リアクションを追加
--- @param message_ts string メッセージのタイムスタンプ
--- @param emoji string|nil 絵文字名
--- @return nil
function M.add_reaction(message_ts, emoji)
  local channel_id = state.get_current_channel()
  
  if not channel_id then
    notify('現在のチャンネルが設定されていません。メッセージ一覧を表示してからリアクションを追加してください。', vim.log.levels.ERROR)
    return
  end
  
  -- リアクション追加処理
  local function do_react(reaction)
    api.add_reaction(message_ts, reaction, function(success)
      -- 成功/失敗の通知はAPI層で行われる
      if success then
        -- リアクション追加成功イベントを発行
        events.emit('reaction_added_success', message_ts, reaction)
        
        -- スレッドが表示されている場合は、スレッド一覧を更新
        local current_thread_ts = state.get_current_thread()
        if current_thread_ts then
          M.list_thread_replies(current_thread_ts)
        else
          -- 現在表示中のメッセージ一覧を更新
          M.list_messages(channel_id)
        end
      else
        -- リアクション追加失敗イベントを発行
        events.emit('reaction_added_failure', message_ts, reaction)
      end
    end)
  end
  
  if not emoji then
    -- インタラクティブモードで絵文字を入力
    vim.ui.input({ prompt = 'リアクション (例: thumbsup): ' }, function(input)
      if input and input ~= '' then
        do_react(input)
      end
    end)
  else
    do_react(emoji)
  end
end

--------------------------------------------------
-- ファイル関連の関数
--------------------------------------------------

--- ファイルをアップロード
--- @param channel string|nil チャンネル名またはID
--- @param file_path string|nil ファイルパス
--- @return nil
function M.upload_file(channel, file_path)
  -- チャンネルが指定されていない場合は、現在のチャンネルまたはデフォルトチャンネルを使用
  local channel_id = state.get_current_channel()
  channel = channel or channel_id or config.get('default_channel')
  
  -- ファイルアップロード処理
  local function do_upload(path)
    api.upload_file(channel, path, function(success)
      -- 成功/失敗の通知はAPI層で行われる
      if success then
        -- ファイルアップロード成功イベントを発行
        events.emit('file_uploaded_success', channel, path)
        -- 現在表示中のメッセージ一覧を更新
        M.list_messages(channel)
      else
        -- ファイルアップロード失敗イベントを発行
        events.emit('file_uploaded_failure', channel, path)
      end
    end)
  end
  
  if not file_path then
    -- インタラクティブモードでファイルパスを入力
    vim.ui.input({ prompt = 'ファイルパス: ' }, function(input)
      if input and input ~= '' then
        do_upload(input)
      end
    end)
  else
    do_upload(file_path)
  end
end

-- コアモジュールをエクスポート
M.core = core
M.events = events

return M