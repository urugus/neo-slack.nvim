-- neo-slack プラグインのメインモジュール

local M = {}

-- デフォルト設定
M.config = {
  token = '',
  default_channel = 'general',
  refresh_interval = 30,
  notification = true,
  keymaps = {
    toggle = '<leader>ss',
    channels = '<leader>sc',
    messages = '<leader>sm',
    reply = '<leader>sr',
    react = '<leader>se',
  }
}

-- プラグインの初期化
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend('force', M.config, opts)
  
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
  
  -- トークンが設定されているか確認
  if M.config.token == '' then
    vim.notify('Neo-Slack: Slackトークンが設定されていません。', vim.log.levels.ERROR)
    return
  end
  
  -- APIクライアントの初期化
  require('neo-slack.api').setup(M.config.token)
  
  -- 通知システムの初期化
  if M.config.notification then
    require('neo-slack.notification').setup(M.config.refresh_interval)
  end
  
  vim.notify('Neo-Slack: 初期化完了', vim.log.levels.INFO)
end

-- Slackの接続状態を表示
function M.status()
  local api = require('neo-slack.api')
  api.test_connection(function(success, data)
    if success then
      vim.notify('Neo-Slack: 接続成功 - ワークスペース: ' .. (data.team or 'Unknown'), vim.log.levels.INFO)
    else
      vim.notify('Neo-Slack: 接続失敗 - ' .. (data.error or 'Unknown error'), vim.log.levels.ERROR)
    end
  end)
end

-- チャンネル一覧を表示
function M.list_channels()
  local api = require('neo-slack.api')
  local ui = require('neo-slack.ui')
  
  api.get_channels(function(success, channels)
    if success then
      ui.show_channels(channels)
    else
      vim.notify('Neo-Slack: チャンネル一覧の取得に失敗しました', vim.log.levels.ERROR)
    end
  end)
end

-- メッセージ一覧を表示
function M.list_messages(channel)
  local api = require('neo-slack.api')
  local ui = require('neo-slack.ui')
  
  channel = channel or M.config.default_channel
  
  api.get_messages(channel, function(success, messages)
    if success then
      ui.show_messages(channel, messages)
    else
      vim.notify('Neo-Slack: メッセージの取得に失敗しました', vim.log.levels.ERROR)
    end
  end)
end

-- メッセージを送信
function M.send_message(channel, ...)
  local api = require('neo-slack.api')
  
  channel = channel or M.config.default_channel
  local message = table.concat({...}, ' ')
  
  if message == '' then
    -- インタラクティブモードでメッセージを入力
    vim.ui.input({ prompt = 'メッセージ: ' }, function(input)
      if input and input ~= '' then
        api.send_message(channel, input, function(success)
          if success then
            vim.notify('Neo-Slack: メッセージを送信しました', vim.log.levels.INFO)
            -- 現在表示中のメッセージ一覧を更新
            M.list_messages(channel)
          else
            vim.notify('Neo-Slack: メッセージの送信に失敗しました', vim.log.levels.ERROR)
          end
        end)
      end
    end)
  else
    api.send_message(channel, message, function(success)
      if success then
        vim.notify('Neo-Slack: メッセージを送信しました', vim.log.levels.INFO)
        -- 現在表示中のメッセージ一覧を更新
        M.list_messages(channel)
      else
        vim.notify('Neo-Slack: メッセージの送信に失敗しました', vim.log.levels.ERROR)
      end
    end)
  end
end

-- メッセージに返信
function M.reply_message(message_ts, ...)
  local api = require('neo-slack.api')
  
  local reply = table.concat({...}, ' ')
  
  if reply == '' then
    -- インタラクティブモードで返信を入力
    vim.ui.input({ prompt = '返信: ' }, function(input)
      if input and input ~= '' then
        api.reply_message(message_ts, input, function(success)
          if success then
            vim.notify('Neo-Slack: 返信を送信しました', vim.log.levels.INFO)
          else
            vim.notify('Neo-Slack: 返信の送信に失敗しました', vim.log.levels.ERROR)
          end
        end)
      end
    end)
  else
    api.reply_message(message_ts, reply, function(success)
      if success then
        vim.notify('Neo-Slack: 返信を送信しました', vim.log.levels.INFO)
      else
        vim.notify('Neo-Slack: 返信の送信に失敗しました', vim.log.levels.ERROR)
      end
    end)
  end
end

-- リアクションを追加
function M.add_reaction(message_ts, emoji)
  local api = require('neo-slack.api')
  
  if not emoji then
    -- インタラクティブモードで絵文字を入力
    vim.ui.input({ prompt = 'リアクション (例: thumbsup): ' }, function(input)
      if input and input ~= '' then
        api.add_reaction(message_ts, input, function(success)
          if success then
            vim.notify('Neo-Slack: リアクションを追加しました', vim.log.levels.INFO)
          else
            vim.notify('Neo-Slack: リアクションの追加に失敗しました', vim.log.levels.ERROR)
          end
        end)
      end
    end)
  else
    api.add_reaction(message_ts, emoji, function(success)
      if success then
        vim.notify('Neo-Slack: リアクションを追加しました', vim.log.levels.INFO)
      else
        vim.notify('Neo-Slack: リアクションの追加に失敗しました', vim.log.levels.ERROR)
      end
    end)
  end
end

-- ファイルをアップロード
function M.upload_file(channel, file_path)
  local api = require('neo-slack.api')
  
  channel = channel or M.config.default_channel
  
  if not file_path then
    -- インタラクティブモードでファイルパスを入力
    vim.ui.input({ prompt = 'ファイルパス: ' }, function(input)
      if input and input ~= '' then
        api.upload_file(channel, input, function(success)
          if success then
            vim.notify('Neo-Slack: ファイルをアップロードしました', vim.log.levels.INFO)
          else
            vim.notify('Neo-Slack: ファイルのアップロードに失敗しました', vim.log.levels.ERROR)
          end
        end)
      end
    end)
  else
    api.upload_file(channel, file_path, function(success)
      if success then
        vim.notify('Neo-Slack: ファイルをアップロードしました', vim.log.levels.INFO)
      else
        vim.notify('Neo-Slack: ファイルのアップロードに失敗しました', vim.log.levels.ERROR)
      end
    end)
  end
end

return M