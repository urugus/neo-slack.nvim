---@brief [[
--- neo-slack.nvim API メッセージモジュール
--- メッセージの取得と送信を行います
--- 改良版：依存性注入パターンを活用
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_utils() return dependency.get('utils') end
local function get_api_utils() return dependency.get('api.utils') end
local function get_events() return dependency.get('core.events') end
local function get_api_core() return dependency.get('api.core') end
local function get_api_channels() return dependency.get('api.channels') end

---@class NeoSlackAPIMessages
local M = {}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
---@return nil
local function notify(message, level, opts)
  get_api_utils().notify(message, level, opts)
end

-- これらの関数は不要になりました（依存性注入で置き換え）

--- メッセージ一覧を取得（Promise版）
--- @param channel string チャンネル名またはID
--- @param options table|nil 追加オプション
--- @return table Promise
function M.get_messages_promise(channel, options)
  options = options or {}

  -- チャンネルIDを取得
  local channel_id_promise = get_api_channels().get_channel_id_promise(channel)

  -- 最初のPromise: チャンネルIDを取得
  local messages_promise = get_utils().Promise.then_func(channel_id_promise, function(channel_id)
    local params = vim.tbl_extend('force', {
      channel = channel_id,
      limit = 100,
    }, options)

    -- 2番目のPromise: メッセージを取得
    local request_promise = get_api_core().request_promise('GET', 'conversations.history', params)
    return get_utils().Promise.then_func(request_promise, function(data)
      -- デバッグ情報を追加
      notify('APIレスポンス: ' .. vim.inspect(data), vim.log.levels.INFO)

      -- messagesフィールドの確認
      if not data.messages then
        notify('messagesフィールドがありません', vim.log.levels.ERROR)
        return {}
      end

      if #data.messages == 0 then
        notify('メッセージが0件です', vim.log.levels.INFO)
      else
        notify('メッセージ件数: ' .. #data.messages, vim.log.levels.INFO)
      end

      -- メッセージ一覧取得イベントを発行
      get_events().emit('api:messages_loaded', channel_id, data.messages)

      return data.messages
    end)
  end)

  -- エラーハンドリング
  return get_utils().Promise.catch_func(messages_promise, function(err)
    local error_msg = err.error or 'Unknown error'
    notify('メッセージの取得に失敗しました - ' .. error_msg, vim.log.levels.ERROR)
    return get_utils().Promise.reject(err)
  end)
end

--- メッセージ一覧を取得（コールバック版 - 後方互換性のため）
--- @param channel string チャンネル名またはID
--- @param callback function コールバック関数
--- @param options table|nil 追加オプション
--- @return nil
function M.get_messages(channel, callback, options)
  local promise = M.get_messages_promise(channel, options)

  -- Promiseが解決されるのを待ってからコールバックを呼び出す
  promise:next(function(messages)
    vim.schedule(function()
      -- デバッグ情報を追加
      notify('コールバック実行: メッセージ件数=' .. #messages, vim.log.levels.INFO)
      callback(true, messages)
    end)
  end):catch(function(err)
    vim.schedule(function()
      callback(false, err)
      end)
    end
  )
end

--- スレッド返信を取得（Promise版）
--- @param channel string チャンネル名またはID
--- @param thread_ts string スレッドの親メッセージのタイムスタンプ
--- @return table Promise
function M.get_thread_replies_promise(channel, thread_ts)
  -- チャンネルIDを取得
  local channel_id_promise = get_api_channels().get_channel_id_promise(channel)

  -- 最初のPromise: チャンネルIDを取得
  local replies_promise = get_utils().Promise.then_func(channel_id_promise, function(channel_id)
    local params = {
      channel = channel_id,
      ts = thread_ts,
      limit = 100,
      inclusive = true
    }

    -- 2番目のPromise: スレッド返信を取得
    local request_promise = get_api_core().request_promise('GET', 'conversations.replies', params)
    return get_utils().Promise.then_func(request_promise, function(data)
      -- 最初のメッセージは親メッセージなので、返信のみを返す
      local result = {
        replies = {},
        parent_message = nil
      }

      if #data.messages > 0 then
        -- 親メッセージを保存
        result.parent_message = data.messages[1]

        -- 2番目以降のメッセージ（返信）を返す
        if #data.messages > 1 then
          for i = 2, #data.messages do
            table.insert(result.replies, data.messages[i])
          end
        end
      end

      -- スレッド返信取得イベントを発行
      get_events().emit('api:thread_replies_loaded', channel_id, thread_ts, result.replies, result.parent_message)

      return result
    end)
  end)

  -- エラーハンドリング
  return get_utils().Promise.catch_func(replies_promise, function(err)
    -- エラーハンドリング
    local error_msg = err.error or 'Unknown error'

    -- 権限エラーの場合、より詳細な情報を提供
    if error_msg == 'missing_scope' then
      notify('スレッド返信の取得に失敗しました - 権限不足 (missing_scope)\n' ..
             'Slackトークンに必要な権限がありません。\n' ..
             '必要な権限: channels:history, groups:history, im:history, mpim:history\n' ..
             'https://api.slack.com/apps で以下の権限を追加してください:\n' ..
             '- User Token Scopes: channels:history, groups:history, im:history, mpim:history', vim.log.levels.ERROR)
    else
      notify('スレッド返信の取得に失敗しました - ' .. error_msg, vim.log.levels.ERROR)
    end

    -- 修正: utils.Promise.rejectの代わりにget_utils().Promise.rejectを使用
    return get_utils().Promise.reject(err)
  end)
end

--- スレッド返信を取得（コールバック版 - 後方互換性のため）
--- @param channel string チャンネル名またはID
--- @param thread_ts string スレッドの親メッセージのタイムスタンプ
--- @param callback function コールバック関数
--- @return nil
function M.get_thread_replies(channel, thread_ts, callback)
  local promise = M.get_thread_replies_promise(channel, thread_ts)

  get_utils().Promise.catch_func(
    get_utils().Promise.then_func(promise, function(result)
      vim.schedule(function()
        -- デバッグ情報を追加
        notify('スレッド返信取得コールバック実行: 返信件数=' .. #result.replies, vim.log.levels.INFO)
        callback(true, result.replies, result.parent_message)
      end)
    end),
    function(err)
      vim.schedule(function()
        callback(false, err)
      end)
    end
  )
end

--- メッセージを送信（Promise版）
--- @param channel string チャンネル名またはID
--- @param text string メッセージテキスト
--- @param options table|nil 追加オプション
--- @return table Promise
function M.send_message_promise(channel, text, options)
  options = options or {}

  -- チャンネルIDを取得
  local channel_id_promise = get_api_channels().get_channel_id_promise(channel)

  -- 最初のPromise: チャンネルIDを取得
  local message_promise = get_utils().Promise.then_func(channel_id_promise, function(channel_id)
    local params = vim.tbl_extend('force', {
      channel = channel_id,
      text = text,
    }, options)

    -- 2番目のPromise: メッセージを送信
    local request_promise = get_api_core().request_promise('POST', 'chat.postMessage', params)
    return get_utils().Promise.then_func(request_promise, function(data)
      notify('メッセージを送信しました', vim.log.levels.INFO)

      -- メッセージ送信イベントを発行
      get_events().emit('api:message_sent', channel_id, text, data)

      return data
    end)
  end)

  -- エラーハンドリング
  return get_utils().Promise.catch_func(message_promise, function(err)
    local error_msg = err.error or 'Unknown error'
    notify('メッセージの送信に失敗しました - ' .. error_msg, vim.log.levels.ERROR)

    -- メッセージ送信失敗イベントを発行
    get_events().emit('api:message_sent_failure', channel, text, err)

    return get_utils().Promise.reject(err)
  end)
end

--- メッセージを送信（コールバック版 - 後方互換性のため）
--- @param channel string チャンネル名またはID
--- @param text string メッセージテキスト
--- @param callback function コールバック関数
--- @return nil
function M.send_message(channel, text, callback)
  local promise = M.send_message_promise(channel, text)

  get_utils().Promise.catch_func(
    get_utils().Promise.then_func(promise, function()
      vim.schedule(function()
        callback(true)
      end)
    end),
    function()
      vim.schedule(function()
        callback(false)
      end)
    end
  )
end

--- メッセージに返信（Promise版）
--- @param message_ts string メッセージのタイムスタンプ
--- @param text string 返信テキスト
--- @param channel_id string|nil チャンネルID（nilの場合は現在のチャンネルを使用）
--- @param options table|nil 追加オプション
--- @return table Promise
function M.reply_message_promise(message_ts, text, channel_id, options)
  options = options or {}

  return get_utils().Promise.new(function(resolve, reject)
    -- チャンネルIDが指定されていない場合は、イベントを発行して取得
    if not channel_id then
      -- 現在のチャンネルIDを取得するためのイベントを発行
      get_events().emit('api:get_current_channel')

      -- イベントハンドラを一度だけ登録
      get_events().once('api:current_channel', function(current_channel_id)
        if not current_channel_id then
          notify('現在のチャンネルIDが設定されていません。メッセージ一覧を表示してから返信してください。', vim.log.levels.ERROR)
          reject({ error = 'チャンネルIDが設定されていません' })
          return
        end

        -- 取得したチャンネルIDで再帰的に呼び出し
        local promise = M.reply_message_promise(message_ts, text, current_channel_id, options)
        get_utils().Promise.catch_func(
          get_utils().Promise.then_func(promise, resolve),
          reject
        )
      end)

      return
    end

    -- チャンネルIDが指定されている場合は、メッセージを送信
    local params = vim.tbl_extend('force', {
      channel = channel_id,
      text = text,
      thread_ts = message_ts,
    }, options)

    local request_promise = get_api_core().request_promise('POST', 'chat.postMessage', params)

    get_utils().Promise.catch_func(
      get_utils().Promise.then_func(request_promise, function(data)
        notify('返信を送信しました', vim.log.levels.INFO)

        -- 返信送信イベントを発行
        get_events().emit('api:message_replied', channel_id, message_ts, text, data)

        resolve(data)
      end),
      function(err)
        local error_msg = err.error or 'Unknown error'
        notify('返信の送信に失敗しました - ' .. error_msg, vim.log.levels.ERROR)

        -- 返信送信失敗イベントを発行
        get_events().emit('api:message_replied_failure', channel_id, message_ts, text, err)

        reject(err)
      end
    )
  end)
end

--- メッセージに返信（コールバック版 - 後方互換性のため）
--- @param message_ts string メッセージのタイムスタンプ
--- @param text string 返信テキスト
--- @param callback function コールバック関数
--- @return nil
function M.reply_message(message_ts, text, callback)
  local promise = M.reply_message_promise(message_ts, text)

  get_utils().Promise.catch_func(
    get_utils().Promise.then_func(promise, function()
      vim.schedule(function()
        callback(true)
      end)
    end),
    function()
      vim.schedule(function()
        callback(false)
      end)
    end
  )
end

return M