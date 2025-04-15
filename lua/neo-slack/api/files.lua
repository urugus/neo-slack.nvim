---@brief [[
--- neo-slack.nvim API ファイルモジュール
--- ファイルのアップロードを行います
---@brief ]]

local utils = require('neo-slack.utils')
local api_utils = require('neo-slack.api.utils')
local events = require('neo-slack.core.events')

---@class NeoSlackAPIFiles
local M = {}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
---@return nil
local function notify(message, level, opts)
  api_utils.notify(message, level, opts)
end

-- APIコアモジュールとチャンネルモジュールへの参照を保持する変数
local core
local channels

-- 必要なモジュールを取得する関数
local function get_core()
  if not core then
    core = require('neo-slack.api.core')
  end
  return core
end

local function get_channels()
  if not channels then
    channels = require('neo-slack.api.channels')
  end
  return channels
end

--- ファイルをアップロード（Promise版）
--- @param channel string チャンネル名またはID
--- @param file_path string ファイルパス
--- @param options table|nil 追加オプション
--- @return table Promise
function M.upload_file_promise(channel, file_path, options)
  options = options or {}

  -- チャンネルIDを取得
  local channel_id_promise = get_channels().get_channel_id_promise(channel)

  return utils.Promise.then_func(channel_id_promise, function(channel_id)
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
        vim.fn.shellescape(get_core().config.token)
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
  local promise = M.upload_file_promise(channel, file_path)
  utils.Promise.catch_func(
    utils.Promise.then_func(promise, function()
      vim.schedule(function()
        callback(true)
      end)
    end),
    function()
      vim.schedule(function()
        callback(false)
      end)
    end
  )
end

return M