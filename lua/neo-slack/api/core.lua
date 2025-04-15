---@brief [[
--- neo-slack.nvim API コアモジュール
--- API通信の基本機能を提供します
---@brief ]]

local utils = require('neo-slack.utils')
local api_utils = require('neo-slack.api.utils')
local events = require('neo-slack.core.events')

---@class NeoSlackAPICore
---@field config APIConfig API設定
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

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
---@return nil
local function notify(message, level, opts)
  api_utils.notify(message, level, opts)
end

--- APIの初期化
--- @param token string Slack APIトークン
--- @return nil
function M.setup(token)
  M.config.token = token
end

--- APIリクエストを実行（Promise版）
--- @param method string HTTPメソッド ('GET' or 'POST')
--- @param endpoint string APIエンドポイント
--- @param params table|nil リクエストパラメータ
--- @param options table|nil リクエストオプション
--- @return table Promise
function M.request_promise(method, endpoint, params, options)
  return api_utils.request_promise(
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
M.request = api_utils.create_callback_version(M.request_promise)

--- 接続テスト（Promise版）
--- @return table Promise
function M.test_connection_promise()
  local promise = M.request_promise('GET', 'auth.test', {})

  -- utils.Promise.then_funcとcatch_funcを使用
  return utils.Promise.catch_func(
    utils.Promise.then_func(promise, function(data)
      -- チーム情報を保存
      M.config.team_info = data

      -- 接続成功イベントを発行
      events.emit('api:connected', data)

      return data
    end),
    function(err)
      -- 接続失敗イベントを発行
      events.emit('api:connection_failed', err)

      return utils.Promise.reject(err)
    end
  )
end

--- 接続テスト（コールバック版 - 後方互換性のため）
--- @param callback function コールバック関数
--- @return nil
M.test_connection = api_utils.create_callback_version(M.test_connection_promise)

--- チーム情報を取得（Promise版）
--- @return table Promise
function M.get_team_info_promise()
  return M.request_promise('GET', 'team.info', {})
end

--- チーム情報を取得（コールバック版 - 後方互換性のため）
--- @param callback function コールバック関数
--- @return nil
M.get_team_info = api_utils.create_callback_version(M.get_team_info_promise)

return M