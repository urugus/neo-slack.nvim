---@brief [[
--- neo-slack.nvim API ユーティリティモジュール
--- API関連の共通ヘルパー関数を提供します
---@brief ]]

local curl = require('plenary.curl')
local json = { encode = vim.json.encode, decode = vim.json.decode }
local utils = require('neo-slack.utils')

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
  utils.notify(message, level, opts)
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

    utils.Promise.catch_func(
      utils.Promise.then_func(promise, function(data)
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

  M.notify('APIリクエスト: ' .. method .. ' ' .. endpoint, vim.log.levels.INFO)

  if not token or token == '' then
    M.notify('APIトークンが設定されていません', vim.log.levels.ERROR)
    return utils.Promise.new(function(_, reject)
      reject({ error = 'APIトークンが設定されていません' })
    end)
  end

  return utils.Promise.new(function(resolve, reject)
    local headers = {
      Authorization = 'Bearer ' .. token,
    }

    local url = base_url .. endpoint
    M.notify('URL: ' .. url, vim.log.levels.INFO)

    local opts = {
      headers = headers,
      callback = function(response)
        if response.status ~= 200 then
          M.notify('HTTPエラー: ' .. response.status, vim.log.levels.ERROR)
          reject({ error = 'HTTP error: ' .. response.status, status = response.status })
          return
        end

        local success, data = pcall(json.decode, response.body)
        if not success then
          M.notify('JSONパースエラー: ' .. data, vim.log.levels.ERROR)
          reject({ error = 'JSON parse error: ' .. data })
          return
        }

        if not data.ok then
          M.notify('APIエラー: ' .. (data.error or 'Unknown API error'), vim.log.levels.ERROR)
          reject({ error = data.error or 'Unknown API error', data = data })
          return
        }

        M.notify('APIリクエスト成功: ' .. endpoint, vim.log.levels.INFO)
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