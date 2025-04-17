---@brief [[
--- neo-slack.nvim API ファイルモジュール
--- ファイルのアップロードを行います
--- 改良版：依存性注入パターンを活用
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_utils() return dependency.get('utils') end
local function get_api_utils() return dependency.get('api.utils') end
local function get_events() return dependency.get('core.events') end
local function get_api_core() return dependency.get('api.core') end
local function get_api_channels() return dependency.get('api.channels') end

---@class NeoSlackAPIFiles
local M = {}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
---@return nil
local function notify(message, level, opts)
  get_api_utils().notify(message, level, opts)
end

-- これらの関数は不要になりました（依存性注入で置き換え）

--- ファイルをアップロード（Promise版）
--- @param channel string チャンネル名またはID
--- @param file_path string ファイルパス
--- @param options table|nil 追加オプション
--- @return table Promise
function M.upload_file_promise(channel, file_path, options)
  options = options or {}

  -- チャンネルIDを取得
  local channel_id_promise = get_api_channels().get_channel_id_promise(channel)

  return get_utils().Promise.then_func(channel_id_promise, function(channel_id)
    return get_utils().Promise.new(function(resolve, reject)
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
        vim.fn.shellescape(get_api_core().config.token)
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
            get_events().emit('api:file_uploaded', channel_id, file_path)
          else
            local error_msg = 'ファイルのアップロードに失敗しました (exit code: ' .. exit_code .. ')'
            notify(error_msg, vim.log.levels.ERROR)

            -- ファイルアップロード失敗イベントを発行
            get_events().emit('api:file_uploaded_failure', channel_id, file_path, { error = error_msg })

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
  get_utils().Promise.catch_func(
    get_utils().Promise.then_func(promise, function()
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