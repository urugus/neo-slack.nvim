---@brief [[
--- neo-slack.nvim API ユーティリティモジュール
--- API関連の共通ヘルパー関数を提供します
--- 改良版：依存性注入パターンを活用
---@brief ]]

local curl = require('plenary.curl')
local json = { encode = vim.json.encode, decode = vim.json.decode }

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_utils() return dependency.get('utils') end
local function get_errors() return dependency.get('core.errors') end

---@class NeoSlackAPIUtils
local M = {}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
---@return nil
function M.notify(message, level, opts)
  opts = opts or {}
  opts.prefix = 'API: '
  get_utils().notify(message, level, opts)
end

-- パラメータ内のブール値を文字列に変換
---@param params table パラメータテーブル
---@return table 変換後のパラメータテーブル
function M.convert_bool_to_string(params)
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

-- Promise版の関数からコールバック版の関数を生成するヘルパー
---@param promise_fn function Promise版の関数
---@return function コールバック版の関数
function M.create_callback_version(promise_fn)
  return function(...)
    local args = {...}
    local callback = args[#args]
    args[#args] = nil

    local promise = promise_fn(unpack(args))

    get_utils().Promise.catch_func(
      get_utils().Promise.then_func(promise, function(data)
        vim.schedule(function()
          callback(true, data)
        end)
      end),
      function(err)
        vim.schedule(function()
          callback(false, err)
        end)
      end
    )
  end
end

-- HTTP APIリクエストを実行（Promise版）
---@param method string HTTPメソッド ('GET' or 'POST')
---@param endpoint string APIエンドポイント
---@param params table|nil リクエストパラメータ
---@param options table|nil リクエストオプション
---@param token string APIトークン
---@param base_url string APIのベースURL
---@return table Promise
function M.request_promise(method, endpoint, params, options, token, base_url)
  params = params or {}
  options = options or {}
  local errors = get_errors()

  M.notify('APIリクエスト: ' .. method .. ' ' .. endpoint, vim.log.levels.INFO)

  if not token or token == '' then
    local error_obj = errors.create_error(
      errors.error_types.AUTH,
      'APIトークンが設定されていません',
      { endpoint = endpoint }
    )
    errors.handle_error(error_obj)
    return get_utils().Promise.new(function(_, reject)
      reject(error_obj)
    end)
  end

  return get_utils().Promise.new(function(resolve, reject)
    local headers = {
      Authorization = 'Bearer ' .. token,
    }

    local url = base_url .. endpoint
    M.notify('URL: ' .. url, vim.log.levels.INFO)

    local opts = {
      headers = headers,
      callback = function(response)
        if response.status ~= 200 then
          local error_obj = errors.create_error(
            errors.error_types.NETWORK,
            'HTTPエラー: ' .. response.status,
            {
              endpoint = endpoint,
              status = response.status,
              method = method
            }
          )
          errors.handle_error(error_obj)
          reject(error_obj)
          return
        end

        local success, data = pcall(json.decode, response.body)
        if not success then
          local error_obj = errors.create_error(
            errors.error_types.API,
            'JSONパースエラー: ' .. data,
            {
              endpoint = endpoint,
              body = response.body:sub(1, 100) -- 最初の100文字だけ保存
            }
          )
          errors.handle_error(error_obj)
          reject(error_obj)
          return
        end

        if not data.ok then
          local error_obj = errors.create_error(
            errors.error_types.API,
            'APIエラー: ' .. (data.error or 'Unknown API error'),
            {
              endpoint = endpoint,
              error_code = data.error,
              data = data
            }
          )
          errors.handle_error(error_obj)
          reject(error_obj)
          return
        end

        M.notify('APIリクエスト成功: ' .. endpoint, vim.log.levels.INFO)

        -- デバッグ情報を追加
        if endpoint == 'conversations.history' then
          M.notify('conversations.history レスポンス: ' .. vim.inspect(data), vim.log.levels.INFO)

          -- messagesフィールドの確認
          if not data.messages then
            M.notify('conversations.history: messagesフィールドがありません', vim.log.levels.ERROR)
          elseif #data.messages == 0 then
            M.notify('conversations.history: メッセージが0件です', vim.log.levels.INFO)
          else
            M.notify('conversations.history: メッセージ件数: ' .. #data.messages, vim.log.levels.INFO)
          end
        end

        resolve(data)
      end
    }

    if method == 'GET' then
      -- GETリクエストの場合、パラメータをURLクエリパラメータとして送信
      -- ブール値を文字列に変換（plenary.curlはブール値を処理できない）
      local string_params = M.convert_bool_to_string(params)
      M.notify('GETリクエストを送信: ' .. vim.inspect(string_params), vim.log.levels.INFO)
      curl.get(url, vim.tbl_extend('force', opts, { query = string_params }))
    elseif method == 'POST' then
      -- POSTリクエストの場合、パラメータをJSONボディとして送信
      opts.headers['Content-Type'] = 'application/json; charset=utf-8'
      opts.body = json.encode(params)
      M.notify('POSTリクエストを送信', vim.log.levels.INFO)
      curl.post(url, opts)
    else
      M.notify('未対応のHTTPメソッド: ' .. method, vim.log.levels.ERROR)
      reject({ error = 'Unsupported HTTP method: ' .. method })
    end
  end)
end

return M