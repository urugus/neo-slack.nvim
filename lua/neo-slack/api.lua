---@brief [[
--- neo-slack API モジュール
--- Slack APIとの通信を処理します
---@brief ]]

local curl = require('plenary.curl')
local json = { encode = vim.json.encode, decode = vim.json.decode }
local utils = require('neo-slack.utils')
local state = require('neo-slack.state')

---@class NeoSlackAPI
---@field config APIConfig API設定
---@field users_cache table ユーザー情報のキャッシュ
local M = {}

-- API設定
---@class APIConfig
---@field base_url string APIのベースURL
---@field token string Slack APIトークン
---@field team_info table|nil チーム情報
---@field user_info table|nil ユーザー情報
M.config = {
  base_url = 'https://slack.com/api/',
  token = '',
  team_info = nil,
  user_info = nil,
}

-- ユーザー情報のキャッシュ
M.users_cache = {}

---@class APIResponse
---@field success boolean 成功したかどうか
---@field data table|nil 成功時のデータ
---@field error string|nil エラー時のメッセージ

---@class APICallback
---@field (fun(success: boolean, data: table|nil): nil)

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
local function notify(message, level)
  vim.notify('Neo-Slack: ' .. message, level)
end

-- パラメータ内のブール値を文字列に変換
---@param params table パラメータテーブル
---@return table 変換後のパラメータテーブル
local function convert_bool_to_string(params)
  local result = {}
  for k, v in pairs(params) do
    if type(v) == "boolean" then
      result[k] = v and "true" or "false"
    else
      result[k] = v
    end
  end
  return result
end

--------------------------------------------------
-- API初期化関連の関数
--------------------------------------------------

--- APIの初期化
--- @param token string Slack APIトークン
--- @return nil
function M.setup(token)
  M.config.token = token
  
  -- チーム情報を取得
  M.get_team_info(function(success, data)
    if success and data and data.team then
      M.config.team_info = data
      notify(data.team.name .. 'に接続しました', vim.log.levels.INFO)
    end
  end)
  
  -- ユーザー情報を取得
  M.get_user_info(function(success, data)
    if success then
      M.config.user_info = data
    end
  end)
end

--- APIリクエストを実行
--- @param method string HTTPメソッド ('GET' or 'POST')
--- @param endpoint string APIエンドポイント
--- @param params table|nil リクエストパラメータ
--- @param callback function コールバック関数
--- @return nil
function M.request(method, endpoint, params, callback)
  params = params or {}
  
  local headers = {
    Authorization = 'Bearer ' .. M.config.token,
  }
  
  local url = M.config.base_url .. endpoint
  
  local opts = {
    headers = headers,
    callback = function(response)
      if response.status ~= 200 then
        vim.schedule(function()
          callback(false, { error = 'HTTP error: ' .. response.status })
        end)
        return
      end
      
      local data = json.decode(response.body)
      
      if not data.ok then
        vim.schedule(function()
          callback(false, { error = data.error or 'Unknown API error' })
        end)
        return
      end
      
      vim.schedule(function()
        callback(true, data)
      end)
    end
  }
  
  if method == 'GET' then
    -- GETリクエストの場合、パラメータをURLクエリパラメータとして送信
    -- ブール値を文字列に変換（plenary.curlはブール値を処理できない）
    local string_params = convert_bool_to_string(params)
    curl.get(url, vim.tbl_extend('force', opts, { query = string_params }))
  elseif method == 'POST' then
    -- POSTリクエストの場合、パラメータをJSONボディとして送信
    opts.headers['Content-Type'] = 'application/json; charset=utf-8'
    opts.body = json.encode(params)
    curl.post(url, opts)
  end
end

--------------------------------------------------
-- 接続・情報取得関連の関数
--------------------------------------------------

--- 接続テスト
--- @param callback function コールバック関数
--- @return nil
function M.test_connection(callback)
  M.request('GET', 'auth.test', {}, callback)
end

--- チーム情報を取得
--- @param callback function コールバック関数
--- @return nil
function M.get_team_info(callback)
  M.request('GET', 'team.info', {}, callback)
end

--- ユーザー情報を取得
--- @param callback function コールバック関数
--- @return nil
function M.get_user_info(callback)
  M.request('GET', 'users.identity', {}, callback)
end

--- 特定のユーザーIDからユーザー情報を取得
--- @param user_id string ユーザーID
--- @param callback function コールバック関数
--- @return nil
function M.get_user_info_by_id(user_id, callback)
  -- キャッシュにユーザー情報があれば、それを返す
  if M.users_cache[user_id] then
    vim.schedule(function()
      callback(true, M.users_cache[user_id])
    end)
    return
  end
  
  -- APIからユーザー情報を取得
  local params = {
    user = user_id
  }
  
  M.request('GET', 'users.info', params, function(success, data)
    if success then
      -- キャッシュに保存
      M.users_cache[user_id] = data.user
      callback(true, data.user)
    else
      local error_msg = data.error or 'Unknown error'
      notify('ユーザー情報の取得に失敗しました - ' .. error_msg, vim.log.levels.WARN)
      callback(false, data)
    end
  end)
end

--- ユーザーIDからユーザー名を取得（非同期）
--- @param user_id string ユーザーID
--- @param callback function コールバック関数
--- @return nil
function M.get_username(user_id, callback)
  M.get_user_info_by_id(user_id, function(success, user_data)
    if success and user_data then
      local display_name = user_data.profile.display_name
      local real_name = user_data.profile.real_name
      
      -- display_nameが空の場合はreal_nameを使用
      local username = (display_name and display_name ~= '') and display_name or real_name
      
      callback(username)
    else
      -- 失敗した場合はユーザーIDをそのまま返す
      callback(user_id)
    end
  end)
end

--------------------------------------------------
-- チャンネル関連の関数
--------------------------------------------------

--- チャンネル一覧を取得
--- @param callback function コールバック関数
--- @return nil
function M.get_channels(callback)
  local params = {
    exclude_archived = true,
    types = 'public_channel,private_channel',
    limit = 1000  -- より多くのチャンネルを取得
  }
  
  M.request('GET', 'conversations.list', params, function(success, data)
    if success then
      callback(true, data.channels)
    else
      local error_msg = data.error or 'Unknown error'
      
      -- 権限エラーの場合、より詳細な情報を提供
      if error_msg == 'missing_scope' then
        -- ユーザートークン（xoxp-）を使用するための情報を追加
        notify('チャンネル一覧の取得に失敗しました - 権限不足 (missing_scope)\n' ..
               'Slackトークンに必要な権限がありません。\n' ..
               '必要な権限: channels:read, groups:read, im:read, mpim:read\n' ..
               'ユーザー自身として送信するには、ボットトークン（xoxb-）ではなく\n' ..
               'ユーザートークン（xoxp-）を使用してください。\n' ..
               '1. https://api.slack.com/apps にアクセス\n' ..
               '2. アプリを選択または新規作成\n' ..
               '3. 左メニューから「OAuth & Permissions」を選択\n' ..
               '4. 「User Token Scopes」に必要な権限を追加\n' ..
               '5. 「Install to Workspace」でアプリをインストール\n' ..
               '6. 「User OAuth Token」をコピー（xoxp-で始まるトークン）\n' ..
               '7. `:SlackResetToken`コマンドでトークンを設定', vim.log.levels.ERROR)
      else
        notify('チャンネル一覧の取得に失敗しました - ' .. error_msg, vim.log.levels.ERROR)
      end
      
      callback(false, data)
    end
  end)
end

--- チャンネル名からチャンネルIDを取得
--- @param channel_name string チャンネル名
--- @param callback function コールバック関数
--- @return nil
function M.get_channel_id(channel_name, callback)
  -- すでにIDの場合はそのまま返す
  if channel_name:match('^[A-Z0-9]+$') then
    callback(channel_name)
    return
  end
  
  -- 状態からチャンネルIDを取得
  local channel_id = state.get_channel_id_by_name(channel_name)
  if channel_id then
    callback(channel_id)
    return
  end
  
  -- チャンネル一覧から検索
  M.get_channels(function(success, channels)
    if not success then
      notify('チャンネル一覧の取得に失敗したため、チャンネルIDを特定できません', vim.log.levels.ERROR)
      callback(nil)
      return
    end
    
    -- 状態にチャンネル一覧を保存
    state.set_channels(channels)
    
    for _, channel in ipairs(channels) do
      if channel.name == channel_name then
        callback(channel.id)
        return
      end
    end
    
    notify('チャンネル "' .. channel_name .. '" が見つかりません', vim.log.levels.ERROR)
    callback(nil)
  end)
end

--------------------------------------------------
-- メッセージ関連の関数
--------------------------------------------------

--- メッセージ一覧を取得
--- @param channel string チャンネル名またはID
--- @param callback function コールバック関数
--- @return nil
function M.get_messages(channel, callback)
  -- チャンネルIDを取得（チャンネル名が指定された場合）
  M.get_channel_id(channel, function(channel_id)
    if not channel_id then
      notify('チャンネルが見つかりません: ' .. channel, vim.log.levels.ERROR)
      callback(false, { error = 'チャンネルが見つかりません: ' .. channel })
      return
    end
    
    local params = {
      channel = channel_id,
      limit = 50,
      inclusive = true
    }
    
    M.request('GET', 'conversations.history', params, function(success, data)
      if success then
        callback(true, data.messages)
      else
        local error_msg = data.error or 'Unknown error'
        
        -- 権限エラーの場合、より詳細な情報を提供
        if error_msg == 'missing_scope' then
          notify('メッセージの取得に失敗しました - 権限不足 (missing_scope)\n' ..
                 'Slackトークンに必要な権限がありません。\n' ..
                 '必要な権限: channels:history, groups:history, im:history, mpim:history\n' ..
                 'https://api.slack.com/apps で以下の権限を追加してください:\n' ..
                 '- User Token Scopes: channels:history, groups:history, im:history, mpim:history', vim.log.levels.ERROR)
        else
          notify('メッセージの取得に失敗しました - ' .. error_msg, vim.log.levels.ERROR)
        end
        
        callback(false, data)
      end
    end)
  end)
end

--- メッセージを送信
--- @param channel string チャンネル名またはID
--- @param text string メッセージテキスト
--- @param callback function コールバック関数
--- @return nil
function M.send_message(channel, text, callback)
  -- チャンネルIDを取得
  M.get_channel_id(channel, function(channel_id)
    if not channel_id then
      notify('チャンネルが見つかりません: ' .. channel, vim.log.levels.ERROR)
      callback(false)
      return
    end
    
    local params = {
      channel = channel_id,
      text = text,
    }
    
    M.request('POST', 'chat.postMessage', params, function(success, data)
      if success then
        notify('メッセージを送信しました', vim.log.levels.INFO)
        callback(true)
      else
        notify('メッセージの送信に失敗しました - ' .. (data.error or 'Unknown error'), vim.log.levels.ERROR)
        callback(false)
      end
    end)
  end)
end

--- メッセージに返信
--- @param message_ts string メッセージのタイムスタンプ
--- @param text string 返信テキスト
--- @param callback function コールバック関数
--- @return nil
function M.reply_message(message_ts, text, callback)
  -- 状態から現在のチャンネルIDを取得
  local channel_id = state.get_current_channel()
  
  if not channel_id then
    notify('現在のチャンネルIDが設定されていません。メッセージ一覧を表示してから返信してください。', vim.log.levels.ERROR)
    callback(false)
    return
  end
  
  local params = {
    channel = channel_id,
    text = text,
    thread_ts = message_ts,
  }
  
  M.request('POST', 'chat.postMessage', params, function(success, data)
    if success then
      notify('返信を送信しました', vim.log.levels.INFO)
      callback(true)
    else
      notify('返信の送信に失敗しました - ' .. (data.error or 'Unknown error'), vim.log.levels.ERROR)
      callback(false)
    end
  end)
end

--------------------------------------------------
-- リアクション関連の関数
--------------------------------------------------

--- リアクションを追加
--- @param message_ts string メッセージのタイムスタンプ
--- @param emoji string 絵文字名
--- @param callback function コールバック関数
--- @return nil
function M.add_reaction(message_ts, emoji, callback)
  -- 状態から現在のチャンネルIDを取得
  local channel_id = state.get_current_channel()
  
  if not channel_id then
    notify('現在のチャンネルIDが設定されていません。メッセージ一覧を表示してからリアクションを追加してください。', vim.log.levels.ERROR)
    callback(false)
    return
  end
  
  -- 絵文字名から「:」を削除
  emoji = emoji:gsub(':', '')
  
  local params = {
    channel = channel_id,
    timestamp = message_ts,
    name = emoji,
  }
  
  M.request('POST', 'reactions.add', params, function(success, data)
    if success then
      notify('リアクションを追加しました', vim.log.levels.INFO)
      callback(true)
    else
      notify('リアクションの追加に失敗しました - ' .. (data.error or 'Unknown error'), vim.log.levels.ERROR)
      callback(false)
    end
  end)
end

--------------------------------------------------
-- ファイル関連の関数
--------------------------------------------------

--- ファイルをアップロード
--- @param channel string チャンネル名またはID
--- @param file_path string ファイルパス
--- @param callback function コールバック関数
--- @return nil
function M.upload_file(channel, file_path, callback)
  -- チャンネルIDを取得
  M.get_channel_id(channel, function(channel_id)
    if not channel_id then
      notify('チャンネルが見つかりません: ' .. channel, vim.log.levels.ERROR)
      callback(false)
      return
    end
    
    -- ファイルの存在確認
    local file = io.open(file_path, 'r')
    if not file then
      notify('ファイルが見つかりません: ' .. file_path, vim.log.levels.ERROR)
      callback(false)
      return
    end
    file:close()
    
    -- curlコマンドを使用してファイルをアップロード
    -- Plenaryのcurlモジュールではマルチパートフォームデータの送信が難しいため、
    -- システムのcurlコマンドを使用
    local cmd = string.format(
      'curl -F file=@%s -F channels=%s -F token=%s https://slack.com/api/files.upload',
      vim.fn.shellescape(file_path),
      vim.fn.shellescape(channel_id),
      vim.fn.shellescape(M.config.token)
    )
    
    vim.fn.jobstart(cmd, {
      on_exit = function(_, exit_code)
        if exit_code == 0 then
          notify('ファイルをアップロードしました', vim.log.levels.INFO)
          callback(true)
        else
          notify('ファイルのアップロードに失敗しました', vim.log.levels.ERROR)
          callback(false)
        end
      end
    })
  end)
end

return M