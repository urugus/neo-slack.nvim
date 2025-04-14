---@brief [[
--- neo-slack.nvim API モジュール
--- Slack APIとの通信を処理します
---@brief ]]

local curl = require('plenary.curl')
local json = { encode = vim.json.encode, decode = vim.json.decode }
local utils = require('neo-slack.utils')
-- stateモジュールへの直接参照を削除し、循環参照を解消
local events = require('neo-slack.core.events')

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
---@param opts table|nil 追加オプション
local function notify(message, level, opts)
  opts = opts or {}
  opts.prefix = 'API: '
  utils.notify(message, level, opts)
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

--- APIリクエストを実行（Promise版）
--- @param method string HTTPメソッド ('GET' or 'POST')
--- @param endpoint string APIエンドポイント
--- @param params table|nil リクエストパラメータ
--- @param options table|nil リクエストオプション
--- @return table Promise
function M.request_promise(method, endpoint, params, options)
  params = params or {}
  options = options or {}
  
  return utils.Promise.new(function(resolve, reject)
    local headers = {
      Authorization = 'Bearer ' .. M.config.token,
    }
    
    local url = M.config.base_url .. endpoint
    
    local opts = {
      headers = headers,
      callback = function(response)
        if response.status ~= 200 then
          reject({ error = 'HTTP error: ' .. response.status, status = response.status })
          return
        end
        
        local success, data = pcall(json.decode, response.body)
        if not success then
          reject({ error = 'JSON parse error: ' .. data })
          return
        end
        
        if not data.ok then
          reject({ error = data.error or 'Unknown API error', data = data })
          return
        end
        
        resolve(data)
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
    else
      reject({ error = 'Unsupported HTTP method: ' .. method })
    end
  end)
end

--- APIリクエストを実行（コールバック版 - 後方互換性のため）
--- @param method string HTTPメソッド ('GET' or 'POST')
--- @param endpoint string APIエンドポイント
--- @param params table|nil リクエストパラメータ
--- @param callback function コールバック関数
--- @return nil
function M.request(method, endpoint, params, callback)
  -- Promiseを使わずに直接実装
  local headers = {
    Authorization = 'Bearer ' .. M.config.token,
  }
  
  local url = M.config.base_url .. endpoint
  
  local opts = {
    headers = headers,
    callback = function(response)
      if response.status ~= 200 then
        vim.schedule(function()
          callback(false, { error = 'HTTP error: ' .. response.status, status = response.status })
        end)
        return
      end
      
      local success, data = pcall(json.decode, response.body)
      if not success then
        vim.schedule(function()
          callback(false, { error = 'JSON parse error: ' .. data })
        end)
        return
      end
      
      if not data.ok then
        vim.schedule(function()
          callback(false, { error = data.error or 'Unknown API error', data = data })
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
    local string_params = convert_bool_to_string(params or {})
    curl.get(url, vim.tbl_extend('force', opts, { query = string_params }))
  elseif method == 'POST' then
    -- POSTリクエストの場合、パラメータをJSONボディとして送信
    opts.headers['Content-Type'] = 'application/json; charset=utf-8'
    opts.body = json.encode(params or {})
    curl.post(url, opts)
  else
    vim.schedule(function()
      callback(false, { error = 'Unsupported HTTP method: ' .. method })
    end)
  end
end

--------------------------------------------------
-- 接続・情報取得関連の関数
--------------------------------------------------

--- 接続テスト（Promise版）
--- @return table Promise
function M.test_connection_promise()
  local promise = M.request_promise('GET', 'auth.test', {})
  
  -- thenメソッドを使用
  local promise_with_then = promise["then"](promise, function(data)
    -- チーム情報を保存
    M.config.team_info = data
    
    -- 接続成功イベントを発行
    events.emit('api:connected', data)
    
    return data
  end)
  
  -- catchメソッドを使用
  return promise_with_then["catch"](promise_with_then, function(err)
    -- 接続失敗イベントを発行
    events.emit('api:connection_failed', err)
    
    return utils.Promise.reject(err)
  end)
end

--- 接続テスト（コールバック版 - 後方互換性のため）
--- @param callback function コールバック関数
--- @return nil
function M.test_connection(callback)
  M.test_connection_promise()
    :then(function(data)
      vim.schedule(function()
        callback(true, data)
      end)
    end)
    :catch(function(err)
      vim.schedule(function()
        callback(false, err)
      end)
    end)
end

--- チーム情報を取得（Promise版）
--- @return table Promise
function M.get_team_info_promise()
  return M.request_promise('GET', 'team.info', {})
end

--- チーム情報を取得（コールバック版 - 後方互換性のため）
--- @param callback function コールバック関数
--- @return nil
function M.get_team_info(callback)
  M.get_team_info_promise()
    :then(function(data)
      vim.schedule(function()
        callback(true, data)
      end)
    end)
    :catch(function(err)
      vim.schedule(function()
        callback(false, err)
      end)
    end)
end

--- ユーザー情報を取得（Promise版）
--- @return table Promise
function M.get_user_info_promise()
  return M.request_promise('GET', 'users.identity', {})
    :then(function(data)
      -- ユーザー情報を保存
      M.config.user_info = data
      
      -- ユーザー情報取得イベントを発行
      events.emit('api:user_info_loaded', data)
      
      return data
    end)
end

--- ユーザー情報を取得（コールバック版 - 後方互換性のため）
--- @param callback function コールバック関数
--- @return nil
function M.get_user_info(callback)
  M.get_user_info_promise()
    :then(function(data)
      vim.schedule(function()
        callback(true, data)
      end)
    end)
    :catch(function(err)
      vim.schedule(function()
        callback(false, err)
      end)
    end)
end

--- 特定のユーザーIDからユーザー情報を取得（Promise版）
--- @param user_id string ユーザーID
--- @return table Promise
function M.get_user_info_by_id_promise(user_id)
  -- キャッシュにユーザー情報があれば、それを返す
  if M.users_cache[user_id] then
    return utils.Promise.new(function(resolve)
      resolve(M.users_cache[user_id])
    end)
  end
  
  -- APIからユーザー情報を取得
  local params = {
    user = user_id
  }
  
  return M.request_promise('GET', 'users.info', params)
    :then(function(data)
      -- キャッシュに保存
      M.users_cache[user_id] = data.user
      
      -- ユーザー情報取得イベントを発行
      events.emit('api:user_info_by_id_loaded', user_id, data.user)
      
      return data.user
    end)
    :catch(function(err)
      local error_msg = err.error or 'Unknown error'
      notify('ユーザー情報の取得に失敗しました - ' .. error_msg, vim.log.levels.WARN)
      return utils.Promise.reject(err)
    end)
end

--- 特定のユーザーIDからユーザー情報を取得（コールバック版 - 後方互換性のため）
--- @param user_id string ユーザーID
--- @param callback function コールバック関数
--- @return nil
function M.get_user_info_by_id(user_id, callback)
  M.get_user_info_by_id_promise(user_id)
    :then(function(user)
      vim.schedule(function()
        callback(true, user)
      end)
    end)
    :catch(function(err)
      vim.schedule(function()
        callback(false, err)
      end)
    end)
end

--- ユーザーIDからユーザー名を取得（Promise版）
--- @param user_id string ユーザーID
--- @return table Promise
function M.get_username_promise(user_id)
  return M.get_user_info_by_id_promise(user_id)
    :then(function(user_data)
      local display_name = user_data.profile.display_name
      local real_name = user_data.profile.real_name
      
      -- display_nameが空の場合はreal_nameを使用
      local username = (display_name and display_name ~= '') and display_name or real_name
      
      return username
    end)
    :catch(function()
      -- 失敗した場合はユーザーIDをそのまま返す
      return user_id
    end)
end

--- ユーザーIDからユーザー名を取得（コールバック版 - 後方互換性のため）
--- @param user_id string ユーザーID
--- @param callback function コールバック関数
--- @return nil
function M.get_username(user_id, callback)
  M.get_username_promise(user_id)
    :then(function(username)
      vim.schedule(function()
        callback(username)
      end)
    end)
end

--------------------------------------------------
-- チャンネル関連の関数
--------------------------------------------------

--- チャンネル一覧を取得（Promise版）
--- @return table Promise
function M.get_channels_promise()
  local params = {
    types = 'public_channel,private_channel,mpim,im',
    exclude_archived = true,
    limit = 1000
  }
  
  return M.request_promise('GET', 'conversations.list', params)
    :then(function(data)
      -- チャンネル一覧取得イベントを発行
      events.emit('api:channels_loaded', data.channels)
      
      return data.channels
    end)
    :catch(function(err)
      local error_msg = err.error or 'Unknown error'
      notify('チャンネル一覧の取得に失敗しました - ' .. error_msg, vim.log.levels.ERROR)
      return utils.Promise.reject(err)
    end)
end

--- チャンネル一覧を取得（コールバック版 - 後方互換性のため）
--- @param callback function コールバック関数
--- @return nil
function M.get_channels(callback)
  M.get_channels_promise()
    :then(function(channels)
      vim.schedule(function()
        callback(true, channels)
      end)
    end)
    :catch(function(err)
      vim.schedule(function()
        callback(false, err)
      end)
    end)
end

--- チャンネル名からチャンネルIDを取得（Promise版）
--- @param channel_name string チャンネル名
--- @return table Promise
function M.get_channel_id_promise(channel_name)
  -- すでにIDの場合はそのまま返す
  if channel_name:match('^[A-Z0-9]+$') then
    return utils.Promise.new(function(resolve)
      resolve(channel_name)
    end)
  end
  
  -- イベントを発行してチャンネルIDを取得
  return utils.Promise.new(function(resolve, reject)
    -- チャンネル一覧を取得
    M.get_channels_promise()
      :then(function(channels)
        for _, channel in ipairs(channels) do
          if channel.name == channel_name then
            -- チャンネルIDを発見
            resolve(channel.id)
            return
          end
        end
        
        -- チャンネルが見つからない場合
        notify('チャンネル "' .. channel_name .. '" が見つかりません', vim.log.levels.ERROR)
        reject({ error = 'チャンネルが見つかりません: ' .. channel_name })
      end)
      :catch(function(err)
        notify('チャンネル一覧の取得に失敗したため、チャンネルIDを特定できません', vim.log.levels.ERROR)
        reject(err)
      end)
  end)
end

--- チャンネル名からチャンネルIDを取得（コールバック版 - 後方互換性のため）
--- @param channel_name string チャンネル名
--- @param callback function コールバック関数
--- @return nil
function M.get_channel_id(channel_name, callback)
  M.get_channel_id_promise(channel_name)
    :then(function(channel_id)
      vim.schedule(function()
        callback(channel_id)
      end)
    end)
    :catch(function()
      vim.schedule(function()
        callback(nil)
      end)
    end)
end

--------------------------------------------------
-- メッセージ関連の関数
--------------------------------------------------

-- メッセージ一覧を取得する関数は前半で既に定義されているため削除

--- スレッド返信を取得（Promise版）
--- @param channel string チャンネル名またはID
--- @param thread_ts string スレッドの親メッセージのタイムスタンプ
--- @return table Promise
function M.get_thread_replies_promise(channel, thread_ts)
  -- チャンネルIDを取得
  return M.get_channel_id_promise(channel)
    :then(function(channel_id)
      local params = {
        channel = channel_id,
        ts = thread_ts,
        limit = 100,
        inclusive = true
      }
      
      return M.request_promise('GET', 'conversations.replies', params)
        :then(function(data)
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
          events.emit('api:thread_replies_loaded', channel_id, thread_ts, result.replies, result.parent_message)
          
          return result
        end)
    end)
    :catch(function(err)
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
      
      return utils.Promise.reject(err)
    end)
end

--- スレッド返信を取得（コールバック版 - 後方互換性のため）
--- @param channel string チャンネル名またはID
--- @param thread_ts string スレッドの親メッセージのタイムスタンプ
--- @param callback function コールバック関数
--- @return nil
function M.get_thread_replies(channel, thread_ts, callback)
  M.get_thread_replies_promise(channel, thread_ts)
    :then(function(result)
      vim.schedule(function()
        callback(true, result.replies, result.parent_message)
      end)
    end)
    :catch(function(err)
      vim.schedule(function()
        callback(false, err)
      end)
    end)
end

--- メッセージを送信（Promise版）
--- @param channel string チャンネル名またはID
--- @param text string メッセージテキスト
--- @param options table|nil 追加オプション
--- @return table Promise
function M.send_message_promise(channel, text, options)
  options = options or {}
  
  -- チャンネルIDを取得
  return M.get_channel_id_promise(channel)
    :then(function(channel_id)
      local params = vim.tbl_extend('force', {
        channel = channel_id,
        text = text,
      }, options)
      
      return M.request_promise('POST', 'chat.postMessage', params)
        :then(function(data)
          notify('メッセージを送信しました', vim.log.levels.INFO)
          
          -- メッセージ送信イベントを発行
          events.emit('api:message_sent', channel_id, text, data)
          
          return data
        end)
    end)
    :catch(function(err)
      local error_msg = err.error or 'Unknown error'
      notify('メッセージの送信に失敗しました - ' .. error_msg, vim.log.levels.ERROR)
      
      -- メッセージ送信失敗イベントを発行
      events.emit('api:message_sent_failure', channel, text, err)
      
      return utils.Promise.reject(err)
    end)
end

--- メッセージを送信（コールバック版 - 後方互換性のため）
--- @param channel string チャンネル名またはID
--- @param text string メッセージテキスト
--- @param callback function コールバック関数
--- @return nil
function M.send_message(channel, text, callback)
  M.send_message_promise(channel, text)
    :then(function()
      vim.schedule(function()
        callback(true)
      end)
    end)
    :catch(function()
      vim.schedule(function()
        callback(false)
      end)
    end)
end

--- メッセージに返信（Promise版）
--- @param message_ts string メッセージのタイムスタンプ
--- @param text string 返信テキスト
--- @param channel_id string|nil チャンネルID（nilの場合は現在のチャンネルを使用）
--- @param options table|nil 追加オプション
--- @return table Promise
function M.reply_message_promise(message_ts, text, channel_id, options)
  options = options or {}
  
  return utils.Promise.new(function(resolve, reject)
    -- チャンネルIDが指定されていない場合は、イベントを発行して取得
    if not channel_id then
      -- 現在のチャンネルIDを取得するためのイベントを発行
      events.emit('api:get_current_channel')
      
      -- イベントハンドラを一度だけ登録
      events.once('api:current_channel', function(current_channel_id)
        if not current_channel_id then
          notify('現在のチャンネルIDが設定されていません。メッセージ一覧を表示してから返信してください。', vim.log.levels.ERROR)
          reject({ error = 'チャンネルIDが設定されていません' })
          return
        end
        
        -- 取得したチャンネルIDで再帰的に呼び出し
        M.reply_message_promise(message_ts, text, current_channel_id, options)
          :then(resolve)
          :catch(reject)
      end)
      
      return
    end
    
    -- チャンネルIDが指定されている場合は、メッセージを送信
    local params = vim.tbl_extend('force', {
      channel = channel_id,
      text = text,
      thread_ts = message_ts,
    }, options)
    
    M.request_promise('POST', 'chat.postMessage', params)
      :then(function(data)
        notify('返信を送信しました', vim.log.levels.INFO)
        
        -- 返信送信イベントを発行
        events.emit('api:message_replied', channel_id, message_ts, text, data)
        
        resolve(data)
      end)
      :catch(function(err)
        local error_msg = err.error or 'Unknown error'
        notify('返信の送信に失敗しました - ' .. error_msg, vim.log.levels.ERROR)
        
        -- 返信送信失敗イベントを発行
        events.emit('api:message_replied_failure', channel_id, message_ts, text, err)
        
        reject(err)
      end)
  end)
end

--- メッセージに返信（コールバック版 - 後方互換性のため）
--- @param message_ts string メッセージのタイムスタンプ
--- @param text string 返信テキスト
--- @param callback function コールバック関数
--- @return nil
function M.reply_message(message_ts, text, callback)
  M.reply_message_promise(message_ts, text)
    :then(function()
      vim.schedule(function()
        callback(true)
      end)
    end)
    :catch(function()
      vim.schedule(function()
        callback(false)
      end)
    end)
end

--------------------------------------------------
-- リアクション関連の関数
--------------------------------------------------

--- リアクションを追加（Promise版）
--- @param message_ts string メッセージのタイムスタンプ
--- @param emoji string 絵文字名
--- @param channel_id string|nil チャンネルID（nilの場合は現在のチャンネルを使用）
--- @return table Promise
function M.add_reaction_promise(message_ts, emoji, channel_id)
  return utils.Promise.new(function(resolve, reject)
    -- チャンネルIDが指定されていない場合は、イベントを発行して取得
    if not channel_id then
      -- 現在のチャンネルIDを取得するためのイベントを発行
      events.emit('api:get_current_channel')
      
      -- イベントハンドラを一度だけ登録
      events.once('api:current_channel', function(current_channel_id)
        if not current_channel_id then
          notify('現在のチャンネルIDが設定されていません。メッセージ一覧を表示してからリアクションを追加してください。', vim.log.levels.ERROR)
          reject({ error = 'チャンネルIDが設定されていません' })
          return
        end
        
        -- 取得したチャンネルIDで再帰的に呼び出し
        M.add_reaction_promise(message_ts, emoji, current_channel_id)
          :then(resolve)
          :catch(reject)
      end)
      
      return
    end
    
    -- 絵文字名から「:」を削除
    emoji = emoji:gsub(':', '')
    
    local params = {
      channel = channel_id,
      timestamp = message_ts,
      name = emoji,
    }
    
    M.request_promise('POST', 'reactions.add', params)
      :then(function(data)
        notify('リアクションを追加しました', vim.log.levels.INFO)
        
        -- リアクション追加イベントを発行
        events.emit('api:reaction_added', channel_id, message_ts, emoji, data)
        
        resolve(data)
      end)
      :catch(function(err)
        local error_msg = err.error or 'Unknown error'
        notify('リアクションの追加に失敗しました - ' .. error_msg, vim.log.levels.ERROR)
        
        -- リアクション追加失敗イベントを発行
        events.emit('api:reaction_added_failure', channel_id, message_ts, emoji, err)
        
        reject(err)
      end)
  end)
end

--- リアクションを追加（コールバック版 - 後方互換性のため）
--- @param message_ts string メッセージのタイムスタンプ
--- @param emoji string 絵文字名
--- @param callback function コールバック関数
--- @return nil
function M.add_reaction(message_ts, emoji, callback)
  M.add_reaction_promise(message_ts, emoji)
    :then(function()
      vim.schedule(function()
        callback(true)
      end)
    end)
    :catch(function()
      vim.schedule(function()
        callback(false)
      end)
    end)
end

--------------------------------------------------
-- ファイル関連の関数
--------------------------------------------------

--- ファイルをアップロード（Promise版）
--- @param channel string チャンネル名またはID
--- @param file_path string ファイルパス
--- @param options table|nil 追加オプション
--- @return table Promise
function M.upload_file_promise(channel, file_path, options)
  options = options or {}
  
  -- チャンネルIDを取得
  return M.get_channel_id_promise(channel)
    :then(function(channel_id)
      return utils.Promise.new(function(resolve, reject)
        -- ファイルの存在確認
        local file = io.open(file_path, 'r')
        if not file then
          notify('ファイルが見つかりません: ' .. file_path, vim.log.levels.ERROR)
          reject({ error = 'ファイルが見つかりません: ' .. file_path })
          return
        end
        file:close()
        
        -- curlコマンドを使用してファイルをアップロード
        -- Plenaryのcurlモジュールではマルチパートフォームデータの送信が難しいため、
        -- システムのcurlコマンドを使用
        local cmd = string.format(
          'curl -s -F file=@%s -F channels=%s -F token=%s https://slack.com/api/files.upload',
          vim.fn.shellescape(file_path),
          vim.fn.shellescape(channel_id),
          vim.fn.shellescape(M.config.token)
        )
        
        -- オプションがあれば追加
        for k, v in pairs(options) do
          cmd = cmd .. string.format(' -F %s=%s', vim.fn.shellescape(k), vim.fn.shellescape(tostring(v)))
        end
        
        vim.fn.jobstart(cmd, {
          on_stdout = function(_, data)
            -- 最後の要素が空文字列の場合は削除
            if data[#data] == '' then
              table.remove(data)
            end
            
            -- 応答がない場合
            if #data == 0 then
              return
            end
            
            -- JSONレスポンスをパース
            local response_text = table.concat(data, '\n')
            local success, response = pcall(vim.json.decode, response_text)
            
            if not success then
              reject({ error = 'JSONパースエラー: ' .. response })
              return
            end
            
            if response.ok then
              resolve(response)
            else
              reject({ error = response.error or 'Unknown error', data = response })
            end
          end,
          on_exit = function(_, exit_code)
            if exit_code == 0 then
              notify('ファイルをアップロードしました', vim.log.levels.INFO)
              
              -- ファイルアップロードイベントを発行
              events.emit('api:file_uploaded', channel_id, file_path)
            else
              local error_msg = 'ファイルのアップロードに失敗しました (exit code: ' .. exit_code .. ')'
              notify(error_msg, vim.log.levels.ERROR)
              
              -- ファイルアップロード失敗イベントを発行
              events.emit('api:file_uploaded_failure', channel_id, file_path, { error = error_msg })
              
              reject({ error = error_msg })
            end
          end
        })
      end)
    end)
end

--- ファイルをアップロード（コールバック版 - 後方互換性のため）
--- @param channel string チャンネル名またはID
--- @param file_path string ファイルパス
--- @param callback function コールバック関数
--- @return nil
function M.upload_file(channel, file_path, callback)
  M.upload_file_promise(channel, file_path)
    :then(function()
      vim.schedule(function()
        callback(true)
      end)
    end)
    :catch(function()
      vim.schedule(function()
        callback(false)
      end)
    end)
end

return M