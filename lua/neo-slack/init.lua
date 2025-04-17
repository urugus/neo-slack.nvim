---@brief [[
--- neo-slack.nvim プラグインのメインモジュール
--- プラグインの初期化と主要な機能を提供します
--- 改良版：依存性注入パターンを活用
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_core() return dependency.get('core') end
local function get_events() return dependency.get('core.events') end
local function get_config() return dependency.get('core.config') end
local function get_initialization() return dependency.get('core.initialization') end
local function get_api() return dependency.get('api') end
local function get_storage() return dependency.get('storage') end
local function get_utils() return dependency.get('utils') end
local function get_notification() return dependency.get('notification') end
local function get_state() return dependency.get('state') end
local function get_ui() return dependency.get('ui') end

---@class NeoSlack
---@field config NeoSlackConfig 設定オブジェクト
local M = {}

-- 設定をエクスポート
-- 設定をエクスポート（遅延ロード）
M.config = setmetatable({}, {
  __index = function(_, key)
    return get_config().current[key]
  end,
  __newindex = function(_, key, value)
    get_config().current[key] = value
  end
})

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
local function notify(message, level)
  get_utils().notify(message, level)
end

--------------------------------------------------
-- 初期化と設定関連の関数
--------------------------------------------------

--- プラグインの初期化
--- @param opts table|nil 設定オプション
--- @param callback function|nil 初期化完了時のコールバック
--- @return boolean 初期化プロセスが開始されたかどうか
function M.setup(opts, callback)
  -- 設定の初期化
  -- 依存性コンテナを初期化
  dependency.initialize()

  -- 設定の初期化
  get_config().setup(opts)

  -- 初期化プロセスを開始
  get_initialization().start(function(success)
    if success then
      notify('初期化が完了しました', vim.log.levels.INFO)

      -- イベントハンドラを登録（循環参照を避けるために明示的に呼び出す）
      M.register_event_handlers()
      notify('イベントハンドラを登録しました', vim.log.levels.DEBUG)

      -- 注意: 自動的にチャンネル一覧を表示しないように変更
      -- チャンネル一覧を表示するには :SlackChannels コマンドを使用してください
    else
      notify('初期化に失敗しました。詳細はログを確認してください。', vim.log.levels.ERROR)
    end

    -- コールバックを呼び出し
    if callback then
      callback(success)
    end
  end)

  return true
end

--- 初期化状態を取得
--- @return table 初期化状態
function M.get_initialization_status()
  notify('初期化状態を確認します', vim.log.levels.INFO)
  local status = get_initialization().get_status()

  -- 初期化状態を表示
  local status_str = '初期化状態: '

  if status.is_initialized then
    status_str = status_str .. '完了'
  elseif status.is_initializing then
    status_str = status_str .. string.format('進行中 (%d/%d)', status.current_step, status.total_steps)
  else
    status_str = status_str .. '未初期化'
  end

  notify(status_str, vim.log.levels.INFO)

  return status
end

--- イベントハンドラを登録
function M.register_event_handlers()
  -- チャンネル選択イベント
  get_events().on('channel_selected', function(channel_id, channel_name)
    M.select_channel(channel_id, channel_name)
  end)

  -- メッセージ送信イベント
  get_events().on('message_sent', function(channel, text)
    M.send_message(channel, text)
  end)

  -- メッセージ返信イベント
  get_events().on('message_replied', function(message_ts, text)
    M.reply_message(message_ts, text)
  end)

  -- スレッド返信イベント
  get_events().on('thread_replied', function(thread_ts, text)
    M.reply_to_thread(thread_ts, text)
  end)

  -- リアクション追加イベント
  get_events().on('reaction_added', function(message_ts, emoji)
    M.add_reaction(message_ts, emoji)
  end)

  -- ファイルアップロードイベント
  get_events().on('file_uploaded', function(channel, file_path)
    M.upload_file(channel, file_path)
  end)

  -- 再接続イベント
  get_events().on('reconnected', function()
    -- 現在のチャンネルのメッセージを更新
    local channel_id = get_state().get_current_channel()
    if channel_id then
      M.list_messages(channel_id)
    end
  end)
end

--- Slackの接続状態を表示
--- @return nil
function M.status()
  notify('接続状態を確認します', vim.log.levels.INFO)

  get_api().test_connection(function(success, data)
    if success then
      notify('接続成功 - ワークスペース: ' .. (data.team or 'Unknown'), vim.log.levels.INFO)

      -- 初期化状態を表示
      local init_status = get_initialization().get_status()
      local status_str = '初期化状態: '

      if init_status.is_initialized then
        status_str = status_str .. '完了'
      elseif init_status.is_initializing then
        status_str = status_str .. string.format('進行中 (%d/%d)', init_status.current_step, init_status.total_steps)
      else
        status_str = status_str .. '未初期化'
      end

      notify(status_str, vim.log.levels.INFO)
    else
      notify('接続失敗 - ' .. (data.error or 'Unknown error'), vim.log.levels.ERROR)
    end
  end)
end

--------------------------------------------------
-- トークン管理関連の関数
--------------------------------------------------

--- トークン入力を促す
--- @param callback function|nil トークン入力後のコールバック
--- @return nil
function M.prompt_for_token(callback)
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
      if callback then
        callback(false)
      end
      return
    end

    -- トークンの検証
    M.validate_and_save_token(input, callback)
  end)
end

--- トークンを検証して保存
--- @param token string Slack APIトークン
--- @param callback function|nil 検証後のコールバック
--- @return nil
function M.validate_and_save_token(token, callback)
  -- 一時的にトークンを設定してテスト
  get_api().setup(token)
  get_api().test_connection(function(success, data)
    if success then
      -- トークンを保存
      if get_storage().save_token(token) then
        notify('トークンを保存しました', vim.log.levels.INFO)

        -- 設定を更新して初期化を続行
        get_config().set('token', token)

        -- 初期化を再開
        get_initialization().start(function(init_success)
          if callback then
            callback(init_success)
          end
        end)
      else
        notify('トークンの保存に失敗しました', vim.log.levels.ERROR)
        if callback then
          callback(false)
        end
      end
    else
      notify('無効なトークンです - ' .. (data.error or 'Unknown error'), vim.log.levels.ERROR)
      -- 再度入力を促す
      vim.defer_fn(function()
        M.prompt_for_token(callback)
      end, 1000)
    end
  end)
end

--- トークンを削除
--- @param prompt_new boolean|nil 新しいトークンの入力を促すかどうか
--- @return boolean 削除に成功したかどうか
function M.delete_token(prompt_new)
  if get_storage().delete_token() then
    get_config().set('token', '')
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
  notify('SlackChannelsコマンドが実行されました', vim.log.levels.INFO)

  -- UIが初期化されているか確認
  local ui_module = get_ui()
  if not ui_module.layout.channels_buf or not vim.api.nvim_buf_is_valid(ui_module.layout.channels_buf) then
    notify('UIを初期化します', vim.log.levels.INFO)
    -- UIを初期化
    ui_module.show()
    -- UIの初期化中にチャンネル一覧を取得するので、ここでは終了
    return
  end

  get_api().get_channels(function(success, channels)
    if success then
      notify('チャンネル一覧の取得に成功しました: ' .. #channels .. '件', vim.log.levels.INFO)
      -- 状態にチャンネル一覧を保存
      get_state().set_channels(channels)
      -- UIにチャンネル一覧を表示
      ui_module.show_channels(channels)
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
  get_state().set_current_channel(channel_id, channel_name)
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
  local channel_id, channel_name = get_state().get_current_channel()
  channel = channel or channel_id or get_config().get('default_channel')

  get_api().get_messages(channel, function(success, messages)
    if success then
      -- 状態にメッセージを保存
      if type(channel) == 'string' then
        get_state().set_messages(channel, messages)
      end
      -- UIにメッセージを表示
      get_ui().show_messages(channel, messages)
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
  local channel_id = get_state().get_current_channel()
  channel = channel or channel_id or get_config().get('default_channel')
  local message = table.concat({...}, ' ')

  -- メッセージ送信処理
  local function do_send(text)
    get_api().send_message(channel, text, function(success)
      if success then
        -- メッセージ送信イベントを発行
        get_events().emit('message_sent_success', channel, text)
        -- 現在表示中のメッセージ一覧を更新
        M.list_messages(channel)
      else
        -- メッセージ送信失敗イベントを発行
        get_events().emit('message_sent_failure', channel, text)
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
  local channel_id = get_state().get_current_channel()

  if not channel_id then
    notify('現在のチャンネルが設定されていません。メッセージ一覧を表示してから返信してください。', vim.log.levels.ERROR)
    return
  end

  -- 返信処理
  local function do_reply(text)
    get_api().reply_message(message_ts, text, function(success)
      -- 成功/失敗の通知はAPI層で行われる
      if success then
        -- 返信成功イベントを発行
        get_events().emit('message_replied_success', message_ts, text)

        -- スレッドが表示されている場合は、スレッド一覧を更新
        local current_thread_ts = get_state().get_current_thread()
        if current_thread_ts == message_ts then
          M.list_thread_replies(message_ts)
        else
          -- 現在表示中のメッセージ一覧を更新
          M.list_messages(channel_id)
        end
      else
        -- 返信失敗イベントを発行
        get_events().emit('message_replied_failure', message_ts, text)
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
  local channel_id = get_state().get_current_channel()

  if not channel_id then
    notify('現在のチャンネルが設定されていません。メッセージ一覧を表示してからスレッドを表示してください。', vim.log.levels.ERROR)
    return
  end

  -- スレッド返信を取得
  get_api().get_thread_replies(channel_id, thread_ts, function(success, replies, parent_message)
    if success then
      -- 状態にスレッド情報を保存
      get_state().set_current_thread(thread_ts, parent_message)
      get_state().set_thread_messages(thread_ts, replies)

      -- UIにスレッド返信を表示
      get_ui().show_thread_replies(thread_ts, replies, parent_message)
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
  local channel_id = get_state().get_current_channel()

  if not channel_id then
    notify('現在のチャンネルが設定されていません。メッセージ一覧を表示してからリアクションを追加してください。', vim.log.levels.ERROR)
    return
  end

  -- リアクション追加処理
  local function do_react(reaction)
    get_api().add_reaction(message_ts, reaction, function(success)
      -- 成功/失敗の通知はAPI層で行われる
      if success then
        -- リアクション追加成功イベントを発行
        get_events().emit('reaction_added_success', message_ts, reaction)

        -- スレッドが表示されている場合は、スレッド一覧を更新
        local current_thread_ts = get_state().get_current_thread()
        if current_thread_ts then
          M.list_thread_replies(current_thread_ts)
        else
          -- 現在表示中のメッセージ一覧を更新
          M.list_messages(channel_id)
        end
      else
        -- リアクション追加失敗イベントを発行
        get_events().emit('reaction_added_failure', message_ts, reaction)
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

return M