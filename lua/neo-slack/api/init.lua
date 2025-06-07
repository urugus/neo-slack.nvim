---@brief [[
--- neo-slack.nvim API モジュール
--- Slack APIとの通信を処理します
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_utils() return dependency.get('utils') end
local function get_events() return dependency.get('core.events') end
local function get_core() return dependency.get('api.core') end
local function get_users() return dependency.get('api.users') end
local function get_channels() return dependency.get('api.channels') end
local function get_messages() return dependency.get('api.messages') end
local function get_reactions() return dependency.get('api.reactions') end
local function get_files() return dependency.get('api.files') end

---@class NeoSlackAPI
---@field config APIConfig API設定
---@field users_cache table ユーザー情報のキャッシュ
local M = {}

-- APIコア設定をエクスポート
M.config = get_core().config

-- ユーザーキャッシュをエクスポート
M.users_cache = get_users().users_cache

--------------------------------------------------
-- API初期化関連の関数
--------------------------------------------------

--- APIの初期化
--- @param token string Slack APIトークン
--- @return nil
function M.setup(token)
  -- コアモジュールの初期化
  get_core().setup(token)

  -- 不要なAPI呼び出しを削除
  -- team.infoとusers.identityは必須ではないため、スコープ要求を減らす
end

--------------------------------------------------
-- コアモジュールの関数をエクスポート
--------------------------------------------------

-- APIリクエスト関数
M.request_promise = function(...) return get_core().request_promise(...) end
M.request = function(...) return get_core().request(...) end

-- 接続テスト関数
M.test_connection_promise = function(...) return get_core().test_connection_promise(...) end
M.test_connection = function(...) return get_core().test_connection(...) end

-- チーム情報取得関数
M.get_team_info_promise = function(...) return get_core().get_team_info_promise(...) end
M.get_team_info = function(...) return get_core().get_team_info(...) end

--------------------------------------------------
-- ユーザーモジュールの関数をエクスポート
--------------------------------------------------

-- ユーザー情報取得関数
M.get_user_info_promise = function(...) return get_users().get_user_info_promise(...) end
M.get_user_info = function(...) return get_users().get_user_info(...) end

-- ユーザーID情報取得関数
M.get_user_info_by_id_promise = function(...) return get_users().get_user_info_by_id_promise(...) end
M.get_user_info_by_id = function(...) return get_users().get_user_info_by_id(...) end

-- ユーザー名取得関数
M.get_username_promise = function(...) return get_users().get_username_promise(...) end
M.get_username = function(...) return get_users().get_username(...) end

--------------------------------------------------
-- チャンネルモジュールの関数をエクスポート
--------------------------------------------------

-- チャンネル一覧取得関数
M.get_channels_promise = function(...) return get_channels().get_channels_promise(...) end
M.get_channels = function(...) return get_channels().get_channels(...) end

-- チャンネルID取得関数
M.get_channel_id_promise = function(...) return get_channels().get_channel_id_promise(...) end
M.get_channel_id = function(...) return get_channels().get_channel_id(...) end

--------------------------------------------------
-- メッセージモジュールの関数をエクスポート
--------------------------------------------------

-- メッセージ一覧取得関数
M.get_messages_promise = function(...) return get_messages().get_messages_promise(...) end
M.get_messages = function(...) return get_messages().get_messages(...) end

-- スレッド返信取得関数
M.get_thread_replies_promise = function(...) return get_messages().get_thread_replies_promise(...) end
M.get_thread_replies = function(...) return get_messages().get_thread_replies(...) end

-- メッセージ送信関数
M.send_message_promise = function(...) return get_messages().send_message_promise(...) end
M.send_message = function(...) return get_messages().send_message(...) end

-- メッセージ返信関数
M.reply_message_promise = function(...) return get_messages().reply_message_promise(...) end
M.reply_message = function(...) return get_messages().reply_message(...) end

--------------------------------------------------
-- リアクションモジュールの関数をエクスポート
--------------------------------------------------

-- リアクション追加関数
M.add_reaction_promise = function(...) return get_reactions().add_reaction_promise(...) end
M.add_reaction = function(...) return get_reactions().add_reaction(...) end

--------------------------------------------------
-- ファイルモジュールの関数をエクスポート
--------------------------------------------------

-- ファイルアップロード関数
M.upload_file_promise = function(...) return get_files().upload_file_promise(...) end
M.upload_file = function(...) return get_files().upload_file(...) end

-- 現在のチャンネルIDを要求するイベントのハンドラを登録
get_events().on('api:get_current_channel', function()
  -- 現在のチャンネルIDを返すイベントを発行
  -- 実際の処理はstate.luaで行われる
end)

return M