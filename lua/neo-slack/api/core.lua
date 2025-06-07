---@brief [[
--- neo-slack.nvim API コアモジュール
--- API通信の基本機能を提供します
--- 改良版：依存性注入パターンを活用
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_utils() return dependency.get('utils') end
local function get_api_utils() return dependency.get('api.utils') end
local function get_events() return dependency.get('core.events') end

---@class NeoSlackAPICore
---@field config APIConfig API設定
local M = {}

-- API設定
---@class APIConfig
---@field base_url string APIのベースURL
---@field token string Slack APIトークン
---@field team_info table|nil チーム情報
---@field user_info table|nil ユーザー情報
---@field scopes string|nil トークンのスコープ
M.config = {
  base_url = 'https://slack.com/api/',
  token = '',
  team_info = nil,
  user_info = nil,
  scopes = nil,
}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
---@return nil
local function notify(message, level, opts)
  get_api_utils().notify(message, level, opts)
end

--- APIの初期化
--- @param token string Slack APIトークン
--- @return nil
function M.setup(token)
  M.config.token = token
  -- スコープ情報をリセット
  M.config.scopes = nil
end

--- APIリクエストを実行（Promise版）
--- @param method string HTTPメソッド ('GET' or 'POST')
--- @param endpoint string APIエンドポイント
--- @param params table|nil リクエストパラメータ
--- @param options table|nil リクエストオプション
--- @return table Promise
function M.request_promise(method, endpoint, params, options)
  return get_api_utils().request_promise(
    method,
    endpoint,
    params,
    options,
    M.config.token,
    M.config.base_url
  )
end

--- APIリクエストを実行（コールバック版 - 後方互換性のため）
--- @param method string HTTPメソッド ('GET' or 'POST')
--- @param endpoint string APIエンドポイント
--- @param params table|nil リクエストパラメータ
--- @param callback function コールバック関数
--- @return nil
M.request = get_api_utils().create_callback_version(M.request_promise)

--- 接続テスト（Promise版）
--- @return table Promise
function M.test_connection_promise()
  local promise = M.request_promise('GET', 'auth.test', {})

  -- utils.Promise.then_funcとcatch_funcを使用
  return get_utils().Promise.catch_func(
    get_utils().Promise.then_func(promise, function(data)
      -- チーム情報を保存
      M.config.team_info = data
      
      -- スコープ情報も保存（auth.testのレスポンスにscopesフィールドがある場合）
      if data.scopes then
        M.config.scopes = data.scopes
      end

      -- 接続成功イベントを発行
      get_events().emit('api:connected', data)

      return data
    end),
    function(err)
      local error_msg = err.error or 'Unknown error'
      local notification = '接続テスト失敗: ' .. error_msg
      
      -- missing_scope エラーの場合、必要なスコープ情報を追加
      if err.error == 'missing_scope' and err.context and err.context.needed_scope then
        notification = notification .. '\n必要なスコープ: ' .. err.context.needed_scope
      end
      
      get_api_utils().notify(notification, vim.log.levels.ERROR)
      -- 接続失敗イベントを発行
      get_events().emit('api:connection_failed', err)

      return get_utils().Promise.reject(err)
    end
  )
end

--- 接続テスト（コールバック版 - 後方互換性のため）
--- @param callback function コールバック関数
--- @return nil
M.test_connection = get_api_utils().create_callback_version(M.test_connection_promise)

--- チーム情報を取得（Promise版）
--- @return table Promise
function M.get_team_info_promise()
  return M.request_promise('GET', 'team.info', {})
end

--- チーム情報を取得（コールバック版 - 後方互換性のため）
--- @param callback function コールバック関数
--- @return nil
M.get_team_info = get_api_utils().create_callback_version(M.get_team_info_promise)

--- 現在のスコープを取得
--- @return string|nil スコープ文字列
function M.get_scopes()
  return M.config.scopes
end

--- 必要なスコープをチェック
--- @param required_scopes table 必要なスコープのリスト
--- @return boolean, table|nil 全てのスコープがあるかtrue、不足スコープのリスト
function M.check_scopes(required_scopes)
  if not M.config.scopes then
    return false, required_scopes
  end
  
  local missing_scopes = {}
  local current_scopes = vim.split(M.config.scopes, ',')
  
  -- 現在のスコープをセットに変換
  local scope_set = {}
  for _, scope in ipairs(current_scopes) do
    scope_set[vim.trim(scope)] = true
  end
  
  -- 必要なスコープをチェック
  for _, required in ipairs(required_scopes) do
    if not scope_set[required] then
      table.insert(missing_scopes, required)
    end
  end
  
  if #missing_scopes > 0 then
    return false, missing_scopes
  end
  
  return true, nil
end

return M