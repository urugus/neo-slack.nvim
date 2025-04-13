---@brief [[
--- neo-slack.nvim 型定義モジュール
--- LuaLS/EmmyLua用の型定義を提供します
---@brief ]]

---@class NeoSlackTypes
local M = {}

-- このファイルは実際には何も返しません。
-- LuaLS/EmmyLuaの型定義のみを提供します。

---@class SlackChannel
---@field id string チャンネルID
---@field name string チャンネル名
---@field is_private boolean プライベートチャンネルかどうか
---@field is_member boolean メンバーかどうか
---@field is_archived boolean アーカイブされているかどうか
---@field num_members number|nil メンバー数
---@field topic table|nil トピック情報
---@field purpose table|nil 目的情報
---@field unread_count number|nil 未読メッセージ数
---@field is_im boolean DMチャンネルかどうか

---@class SlackMessage
---@field type string メッセージタイプ
---@field user string|nil ユーザーID
---@field text string メッセージテキスト
---@field ts string タイムスタンプ
---@field thread_ts string|nil スレッドの親メッセージのタイムスタンプ
---@field reply_count number|nil スレッド返信数
---@field reactions table[]|nil リアクション情報
---@field files table[]|nil 添付ファイル情報
---@field blocks table[]|nil ブロック情報

---@class SlackUser
---@field id string ユーザーID
---@field name string ユーザー名
---@field real_name string 実名
---@field profile table プロフィール情報
---@field is_bot boolean ボットかどうか
---@field is_admin boolean 管理者かどうか

---@class SlackReaction
---@field name string リアクション名（絵文字名）
---@field count number リアクション数
---@field users string[] リアクションしたユーザーのID

---@class SlackFile
---@field id string ファイルID
---@field name string ファイル名
---@field title string タイトル
---@field mimetype string MIMEタイプ
---@field filetype string ファイルタイプ
---@field size number ファイルサイズ（バイト）
---@field url_private string プライベートURL
---@field permalink string パーマリンク

---@class SlackTeam
---@field id string チームID
---@field name string チーム名
---@field domain string ドメイン

---@class APIResponse
---@field success boolean 成功したかどうか
---@field data table|nil 成功時のデータ
---@field error string|nil エラー時のメッセージ

---@class APIError
---@field type string エラータイプ
---@field message string エラーメッセージ
---@field details table|nil 詳細情報
---@field timestamp number タイムスタンプ

---@class NeoSlackLayoutConfig
---@field type string レイアウトタイプ ('split', 'float', 'tab', 'telescope')
---@field channels table チャンネル一覧のレイアウト設定
---@field messages table メッセージ一覧のレイアウト設定
---@field thread table スレッドのレイアウト設定

---@class NeoSlackKeymaps
---@field toggle string トグルキー
---@field channels string チャンネル一覧表示キー
---@field messages string メッセージ一覧表示キー
---@field reply string 返信キー
---@field react string リアクションキー

return M