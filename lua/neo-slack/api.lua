-- neo-slack API モジュール
-- Slack APIとの通信を処理します

local curl = require('plenary.curl')
-- プラグインのバージョンによっては plenary.json が利用できない場合があります
-- 代わりに vim.json を使用します
local json = {}
json.encode = vim.json.encode
json.decode = vim.json.decode

local M = {}

-- API設定
M.config = {
  base_url = 'https://slack.com/api/',
  token = '',
  team_info = nil,
  user_info = nil,
}

-- APIの初期化
function M.setup(token)
  M.config.token = token
  
  -- チーム情報を取得
  M.get_team_info(function(success, data)
    if success then
      M.config.team_info = data
      vim.notify('Neo-Slack: ' .. data.team.name .. 'に接続しました', vim.log.levels.INFO)
    end
  end)
  
  -- ユーザー情報を取得
  M.get_user_info(function(success, data)
    if success then
      M.config.user_info = data
    end
  end)
end

-- APIリクエストを実行
function M.request(method, endpoint, params, callback)
  params = params or {}
  
  local headers = {
    Authorization = 'Bearer ' .. M.config.token,
    ['Content-Type'] = 'application/json; charset=utf-8',
  }
  
  local url = M.config.base_url .. endpoint
  
  local opts = {
    headers = headers,
    body = json.encode(params),
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
    curl.get(url, opts)
  elseif method == 'POST' then
    curl.post(url, opts)
  end
end

-- 接続テスト
function M.test_connection(callback)
  M.request('GET', 'auth.test', {}, callback)
end

-- チーム情報を取得
function M.get_team_info(callback)
  M.request('GET', 'team.info', {}, callback)
end

-- ユーザー情報を取得
function M.get_user_info(callback)
  M.request('GET', 'users.identity', {}, callback)
end

-- チャンネル一覧を取得
function M.get_channels(callback)
  local params = {
    exclude_archived = true,
    types = 'public_channel,private_channel',
  }
  
  M.request('GET', 'conversations.list', params, function(success, data)
    if success then
      callback(true, data.channels)
    else
      callback(false, data)
    end
  end)
end

-- メッセージ一覧を取得
function M.get_messages(channel, callback)
  -- チャンネルIDを取得（チャンネル名が指定された場合）
  M.get_channel_id(channel, function(channel_id)
    if not channel_id then
      callback(false, { error = 'チャンネルが見つかりません: ' .. channel })
      return
    end
    
    local params = {
      channel = channel_id,
      limit = 50,
    }
    
    M.request('GET', 'conversations.history', params, function(success, data)
      if success then
        callback(true, data.messages)
      else
        callback(false, data)
      end
    end)
  end)
end

-- チャンネル名からチャンネルIDを取得
function M.get_channel_id(channel_name, callback)
  -- すでにIDの場合はそのまま返す
  if channel_name:match('^[A-Z0-9]+$') then
    callback(channel_name)
    return
  end
  
  -- チャンネル一覧から検索
  M.get_channels(function(success, channels)
    if not success then
      callback(nil)
      return
    end
    
    for _, channel in ipairs(channels) do
      if channel.name == channel_name then
        callback(channel.id)
        return
      end
    end
    
    callback(nil)
  end)
end

-- メッセージを送信
function M.send_message(channel, text, callback)
  -- チャンネルIDを取得
  M.get_channel_id(channel, function(channel_id)
    if not channel_id then
      callback(false)
      return
    end
    
    local params = {
      channel = channel_id,
      text = text,
    }
    
    M.request('POST', 'chat.postMessage', params, function(success, _)
      callback(success)
    end)
  end)
end

-- メッセージに返信
function M.reply_message(message_ts, text, callback)
  -- メッセージのチャンネルIDを取得（現在の実装では簡略化）
  -- 実際の実装では、UIモジュールから現在のチャンネルIDを取得する必要があります
  local channel_id = vim.g.neo_slack_current_channel_id
  
  if not channel_id then
    callback(false)
    return
  end
  
  local params = {
    channel = channel_id,
    text = text,
    thread_ts = message_ts,
  }
  
  M.request('POST', 'chat.postMessage', params, function(success, _)
    callback(success)
  end)
end

-- リアクションを追加
function M.add_reaction(message_ts, emoji, callback)
  -- メッセージのチャンネルIDを取得（現在の実装では簡略化）
  local channel_id = vim.g.neo_slack_current_channel_id
  
  if not channel_id then
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
  
  M.request('POST', 'reactions.add', params, function(success, _)
    callback(success)
  end)
end

-- ファイルをアップロード
function M.upload_file(channel, file_path, callback)
  -- チャンネルIDを取得
  M.get_channel_id(channel, function(channel_id)
    if not channel_id then
      callback(false)
      return
    end
    
    -- ファイルの存在確認
    local file = io.open(file_path, 'r')
    if not file then
      vim.notify('Neo-Slack: ファイルが見つかりません: ' .. file_path, vim.log.levels.ERROR)
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
          callback(true)
        else
          callback(false)
        end
      end
    })
  end)
end

return M