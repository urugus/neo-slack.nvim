---@brief [[
--- neo-slack プラグインのメインモジュール
--- プラグインの初期化と主要な機能を提供します
---@brief ]]

local api = require('neo-slack.api')
local storage = require('neo-slack.storage')
local utils = require('neo-slack.utils')
local notification = require('neo-slack.notification')
local state = require('neo-slack.state')
-- ui モジュールは循環参照を避けるため、後で読み込む
local ui

---@class NeoSlack
---@field config NeoSlackConfig 設定オブジェクト
local M = {}

-- デフォルト設定
---@class NeoSlackConfig
---@field token string Slack APIトークン
---@field default_channel string デフォルトチャンネル
---@field refresh_interval number 更新間隔（秒）
---@field notification boolean 通知の有効/無効
---@field keymaps table キーマッピング設定
---@field debug boolean デバッグモード
M.config = {
  token = '',
  default_channel = 'general',
  refresh_interval = 30,
  notification = true,
  debug = false,
  keymaps = {
    toggle = '<leader>ss',
    channels = '<leader>sc',
    messages = '<leader>sm',
    reply = '<leader>sr',
    react = '<leader>se',
  }
}

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
  opts = opts or {}
  M.config = utils.deep_merge(M.config, opts)
  
  -- Vimスクリプトから設定を取得（Luaの設定が優先）
  if M.config.token == '' and vim.g.neo_slack_token then
    M.config.token = vim.g.neo_slack_token
  end
  
  if vim.g.neo_slack_default_channel then
    M.config.default_channel = vim.g.neo_slack_default_channel
  end
  
  if vim.g.neo_slack_refresh_interval then
    M.config.refresh_interval = vim.g.neo_slack_refresh_interval
  end
  
  if vim.g.neo_slack_notification ~= nil then
    M.config.notification = vim.g.neo_slack_notification == 1
  end
  
  if vim.g.neo_slack_debug ~= nil then
    M.config.debug = vim.g.neo_slack_debug == 1
  end
  
  -- トークンの取得を試みる（優先順位: 1.設定パラメータ 2.保存済みトークン 3.ユーザー入力）
  if M.config.token == '' then
    -- ストレージからトークンを読み込み
    local saved_token = storage.load_token()
    
    if saved_token then
      M.config.token = saved_token
      notify('保存されたトークンを読み込みました', vim.log.levels.INFO)
    else
      -- トークンの入力を求める
      notify('Slackトークンが必要です', vim.log.levels.INFO)
      M.prompt_for_token()
      return false -- プロンプト後に再度setup()が呼ばれるため、ここで終了
    end
  end
  
  -- APIクライアントの初期化
  api.setup(M.config.token)
  
  -- 通知システムの初期化
  if M.config.notification then
    notification.setup(M.config.refresh_interval)
  end
  
  -- 状態を初期化済みに設定
  state.set_initialized(true)
  
  notify('初期化完了', vim.log.levels.INFO)
  
  if M.config.debug then
    notify('デバッグモードが有効です', vim.log.levels.INFO)
  end
  
  return true
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
        M.config.token = token
        M.setup(M.config)
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
    M.config.token = ''
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
  channel = channel or channel_id or M.config.default_channel
  
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
  channel = channel or channel_id or M.config.default_channel
  local message = table.concat({...}, ' ')
  
  -- メッセージ送信処理
  local function do_send(text)
    api.send_message(channel, text, function(success)
      if success then
        -- 現在表示中のメッセージ一覧を更新
        M.list_messages(channel)
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
        -- スレッドが表示されている場合は、スレッド一覧を更新
        local current_thread_ts = state.get_current_thread()
        if current_thread_ts == message_ts then
          M.list_thread_replies(message_ts)
        else
          -- 現在表示中のメッセージ一覧を更新
          M.list_messages(channel_id)
        end
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
        -- スレッドが表示されている場合は、スレッド一覧を更新
        local current_thread_ts = state.get_current_thread()
        if current_thread_ts then
          M.list_thread_replies(current_thread_ts)
        else
          -- 現在表示中のメッセージ一覧を更新
          M.list_messages(channel_id)
        end
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
  channel = channel or channel_id or M.config.default_channel
  
  -- ファイルアップロード処理
  local function do_upload(path)
    api.upload_file(channel, path, function(success)
      -- 成功/失敗の通知はAPI層で行われる
      if success then
        -- 現在表示中のメッセージ一覧を更新
        M.list_messages(channel)
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

-- 循環参照を避けるため、モジュールの最後でuiを読み込む
ui = require('neo-slack.ui')

return M