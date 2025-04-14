---@brief [[
--- neo-slack.nvim API モジュール
--- Slack APIとの通信を処理します
---@brief ]]

local utils = require('neo-slack.utils')
local events = require('neo-slack.core.events')

---@class NeoSlackAPI
---@field config APIConfig API設定
---@field users_cache table ユーザー情報のキャッシュ
local M = {}

-- サブモジュールを読み込む
local core = require('neo-slack.api.core')
local users = require('neo-slack.api.users')
local channels = require('neo-slack.api.channels')
local messages = require('neo-slack.api.messages')
local reactions = require('neo-slack.api.reactions')
local files = require('neo-slack.api.files')

-- APIコア設定をエクスポート
M.config = core.config

-- ユーザーキャッシュをエクスポート
M.users_cache = users.users_cache

--------------------------------------------------
-- API初期化関連の関数
--------------------------------------------------

--- APIの初期化
--- @param token string Slack APIトークン
--- @return nil
function M.setup(token)
  -- コアモジュールの初期化
  core.setup(token)
  
  -- チーム情報を取得
  M.get_team_info(function(success, data)
    if success and data and data.team then
      M.config.team_info = data
      utils.notify(data.team.name .. 'に接続しました', vim.log.levels.INFO, { prefix = 'API: ' })
    end
  end)
  
  -- ユーザー情報を取得
  M.get_user_info(function(success, data)
    if success then
      M.config.user_info = data
    end
  end)
end

--------------------------------------------------
-- コアモジュールの関数をエクスポート
--------------------------------------------------

-- APIリクエスト関数
M.request_promise = core.request_promise
M.request = core.request

-- 接続テスト関数
M.test_connection_promise = core.test_connection_promise
M.test_connection = core.test_connection

-- チーム情報取得関数
M.get_team_info_promise = core.get_team_info_promise
M.get_team_info = core.get_team_info

--------------------------------------------------
-- ユーザーモジュールの関数をエクスポート
--------------------------------------------------

-- ユーザー情報取得関数
M.get_user_info_promise = users.get_user_info_promise
M.get_user_info = users.get_user_info

-- ユーザーID情報取得関数
M.get_user_info_by_id_promise = users.get_user_info_by_id_promise
M.get_user_info_by_id = users.get_user_info_by_id

-- ユーザー名取得関数
M.get_username_promise = users.get_username_promise
M.get_username = users.get_username

--------------------------------------------------
-- チャンネルモジュールの関数をエクスポート
--------------------------------------------------

-- チャンネル一覧取得関数
M.get_channels_promise = channels.get_channels_promise
M.get_channels = channels.get_channels

-- チャンネルID取得関数
M.get_channel_id_promise = channels.get_channel_id_promise
M.get_channel_id = channels.get_channel_id

--------------------------------------------------
-- メッセージモジュールの関数をエクスポート
--------------------------------------------------

-- メッセージ一覧取得関数
M.get_messages_promise = messages.get_messages_promise
M.get_messages = messages.get_messages

-- スレッド返信取得関数
M.get_thread_replies_promise = messages.get_thread_replies_promise
M.get_thread_replies = messages.get_thread_replies

-- メッセージ送信関数
M.send_message_promise = messages.send_message_promise
M.send_message = messages.send_message

-- メッセージ返信関数
M.reply_message_promise = messages.reply_message_promise
M.reply_message = messages.reply_message

--------------------------------------------------
-- リアクションモジュールの関数をエクスポート
--------------------------------------------------

-- リアクション追加関数
M.add_reaction_promise = reactions.add_reaction_promise
M.add_reaction = reactions.add_reaction

--------------------------------------------------
-- ファイルモジュールの関数をエクスポート
--------------------------------------------------

-- ファイルアップロード関数
M.upload_file_promise = files.upload_file_promise
M.upload_file = files.upload_file

-- 現在のチャンネルIDを要求するイベントのハンドラを登録
events.on('api:get_current_channel', function()
  -- 現在のチャンネルIDを返すイベントを発行
  -- 実際の処理はstate.luaで行われる
end)

return M