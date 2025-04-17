---@brief [[
--- neo-slack.nvim API チャンネルモジュール
--- チャンネル情報の取得と管理を行います
--- 改良版：依存性注入パターンを活用
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_utils() return dependency.get('utils') end
local function get_api_utils() return dependency.get('api.utils') end
local function get_events() return dependency.get('core.events') end
local function get_api_core() return dependency.get('api.core') end

---@class NeoSlackAPIChannels
local M = {}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
---@return nil
local function notify(message, level, opts)
  get_api_utils().notify(message, level, opts)
end

-- この関数は不要になりました（依存性注入で置き換え）

--- チャンネル一覧を取得（Promise版）
--- @return table Promise
function M.get_channels_promise()
  local params = {
    types = "public_channel,private_channel,mpim,im",
    exclude_archived = true,
    limit = 1000
  }

  notify('チャンネル一覧を取得中...', vim.log.levels.INFO)

  local promise = get_api_core().request_promise('GET', 'conversations.list', params)
  return get_utils().Promise.catch_func(
    get_utils().Promise.then_func(promise, function(data)
      -- チャンネル一覧取得イベントを発行
      notify('チャンネル一覧を取得しました: ' .. (data.channels and #data.channels or 0) .. '件', vim.log.levels.INFO)
      get_events().emit('api:channels_loaded', data.channels)

      return data.channels
    end),
    function(err)
      local error_msg = err.error or 'Unknown error'
      notify('チャンネル一覧の取得に失敗しました - ' .. error_msg, vim.log.levels.ERROR)
      return get_utils().Promise.reject(err)
    end
  )
end

--- チャンネル一覧を取得（コールバック版 - 後方互換性のため）
--- @param callback function コールバック関数
--- @return nil
M.get_channels = get_api_utils().create_callback_version(M.get_channels_promise)

--- チャンネル名からチャンネルIDを取得（Promise版）
--- @param channel_name string チャンネル名
--- @return table Promise
function M.get_channel_id_promise(channel_name)
  -- デバッグ情報を追加
  notify('チャンネル名/ID: ' .. tostring(channel_name), vim.log.levels.INFO)

  -- すでにIDの場合はそのまま返す
  if channel_name:match('^[A-Z0-9]+$') then
    notify('IDとして認識: ' .. channel_name, vim.log.levels.INFO)
    return get_utils().Promise.new(function(resolve)
      resolve(channel_name)
    end)
  end

  -- チャンネル一覧を取得するPromiseを作成
  return get_utils().Promise.new(function(resolve, reject)
    -- チャンネル一覧から検索
    M.get_channels(function(success, channels)
      if not success then
        notify('チャンネル一覧の取得に失敗したため、チャンネルIDを特定できません', vim.log.levels.ERROR)
        reject({ error = 'チャンネル一覧の取得に失敗しました' })
        return
      end

      -- デバッグ情報を追加
      notify('チャンネル一覧取得成功: ' .. #channels .. '件', vim.log.levels.INFO)

      -- チャンネル名からIDを検索
      for _, channel in ipairs(channels) do
        notify('チャンネル情報: ' .. vim.inspect({id = channel.id, name = channel.name}), vim.log.levels.DEBUG)
        if channel.name == channel_name then
          notify('チャンネル名一致: ' .. channel_name .. ' -> ' .. channel.id, vim.log.levels.INFO)
          resolve(channel.id)
          return
        end
      end

      notify('チャンネル "' .. channel_name .. '" が見つかりません', vim.log.levels.ERROR)
      reject({ error = 'チャンネルが見つかりません: ' .. channel_name })
    end)
  end)
end

--- チャンネル名からチャンネルIDを取得（コールバック版 - 後方互換性のため）
--- @param channel_name string チャンネル名
--- @param callback function コールバック関数
--- @return nil
function M.get_channel_id(channel_name, callback)
  -- すでにIDの場合はそのまま返す
  if channel_name:match('^[A-Z0-9]+$') then
    callback(channel_name)
    return
  end

  -- チャンネル一覧から検索
  M.get_channels(function(success, channels)
    if not success then
      notify('チャンネル一覧の取得に失敗したため、チャンネルIDを特定できません', vim.log.levels.ERROR)
      callback(nil)
      return
    end

    -- チャンネル名からIDを検索
    for _, channel in ipairs(channels) do
      if channel.name == channel_name then
        callback(channel.id)
        return
      end
    end

    notify('チャンネル "' .. channel_name .. '" が見つかりません', vim.log.levels.ERROR)
    callback(nil)
  end)
end

return M