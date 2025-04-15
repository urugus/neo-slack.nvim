---@brief [[
--- neo-slack.nvim API チャンネルモジュール
--- チャンネル情報の取得と管理を行います
---@brief ]]

local utils = require('neo-slack.utils')
local api_utils = require('neo-slack.api.utils')
local events = require('neo-slack.core.events')

---@class NeoSlackAPIChannels
local M = {}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
---@return nil
local function notify(message, level, opts)
  api_utils.notify(message, level, opts)
end

-- APIコアモジュールへの参照を保持する変数
local core

-- APIコアモジュールを取得する関数
local function get_core()
  if not core then
    core = require('neo-slack.api.core')
  end
  return core
end

--- チャンネル一覧を取得（Promise版）
--- @return table Promise
function M.get_channels_promise()
  local params = {
    types = "public_channel,private_channel,mpim,im",
    exclude_archived = true,
    limit = 1000
  }

  local promise = get_core().request_promise('GET', 'conversations.list', params)
  return utils.Promise.catch_func(
    utils.Promise.then_func(promise, function(data)
      -- チャンネル一覧取得イベントを発行
      events.emit('api:channels_loaded', data.channels)

      return data.channels
    end),
    function(err)
      local error_msg = err.error or 'Unknown error'
      notify('チャンネル一覧の取得に失敗しました - ' .. error_msg, vim.log.levels.ERROR)
      return utils.Promise.reject(err)
    end
  )
end

--- チャンネル一覧を取得（コールバック版 - 後方互換性のため）
--- @param callback function コールバック関数
--- @return nil
M.get_channels = api_utils.create_callback_version(M.get_channels_promise)

--- チャンネル名からチャンネルIDを取得（Promise版）
--- @param channel_name string チャンネル名
--- @return table Promise
function M.get_channel_id_promise(channel_name)
  -- すでにIDの場合はそのまま返す
  if channel_name:match('^[A-Z0-9]+$') then
    return utils.Promise.new(function(resolve)
      resolve(channel_name)
    end)
  end

  -- チャンネル一覧を取得するPromiseを作成
  return utils.Promise.new(function(resolve, reject)
    -- チャンネル一覧から検索
    M.get_channels(function(success, channels)
      if not success then
        notify('チャンネル一覧の取得に失敗したため、チャンネルIDを特定できません', vim.log.levels.ERROR)
        reject({ error = 'チャンネル一覧の取得に失敗しました' })
        return
      end

      -- チャンネル名からIDを検索
      for _, channel in ipairs(channels) do
        if channel.name == channel_name then
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