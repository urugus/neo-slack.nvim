---@brief [[
--- neo-slack.nvim API ユーザーモジュール
--- ユーザー情報の取得と管理を行います
---@brief ]]

local utils = require('neo-slack.utils')
local api_utils = require('neo-slack.api.utils')
local events = require('neo-slack.core.events')

---@class NeoSlackAPIUsers
---@field users_cache table ユーザー情報のキャッシュ
local M = {}

-- ユーザー情報のキャッシュ
M.users_cache = {}

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

--- ユーザー情報を取得（Promise版）
--- @return table Promise
function M.get_user_info_promise()
  local promise = get_core().request_promise('GET', 'users.identity', {})

  return utils.Promise.then_func(promise, function(data)
    -- ユーザー情報を保存
    get_core().config.user_info = data

    -- ユーザー情報取得イベントを発行
    events.emit('api:user_info_loaded', data)

    return data
  end)
end

--- ユーザー情報を取得（コールバック版 - 後方互換性のため）
--- @param callback function コールバック関数
--- @return nil
M.get_user_info = api_utils.create_callback_version(M.get_user_info_promise)

--- 特定のユーザーIDからユーザー情報を取得（Promise版）
--- @param user_id string ユーザーID
--- @return table Promise
function M.get_user_info_by_id_promise(user_id)
  -- キャッシュにユーザー情報があれば、それを返す
  if M.users_cache[user_id] then
    return utils.Promise.new(function(resolve)
      resolve(M.users_cache[user_id])
    end)
  end

  -- APIからユーザー情報を取得
  local params = {
    user = user_id
  }

  local promise = get_core().request_promise('GET', 'users.info', params)

  return utils.Promise.catch_func(
    utils.Promise.then_func(promise, function(data)
      -- キャッシュに保存
      M.users_cache[user_id] = data.user

      -- ユーザー情報取得イベントを発行
      events.emit('api:user_info_by_id_loaded', user_id, data.user)

      return data.user
    end),
    function(err)
      local error_msg = err.error or 'Unknown error'
      notify('ユーザー情報の取得に失敗しました - ' .. error_msg, vim.log.levels.WARN)
      return utils.Promise.reject(err)
    end
  )
end

--- 特定のユーザーIDからユーザー情報を取得（コールバック版 - 後方互換性のため）
--- @param user_id string ユーザーID
--- @param callback function コールバック関数
--- @return nil
M.get_user_info_by_id = api_utils.create_callback_version(M.get_user_info_by_id_promise)

--- ユーザーIDからユーザー名を取得（Promise版）
--- @param user_id string ユーザーID
--- @return table Promise
function M.get_username_promise(user_id)
  local promise = M.get_user_info_by_id_promise(user_id)

  return utils.Promise.catch_func(
    utils.Promise.then_func(promise, function(user_data)
      local display_name = user_data.profile.display_name
      local real_name = user_data.profile.real_name

      -- display_nameが空の場合はreal_nameを使用
      local username = (display_name and display_name ~= '') and display_name or real_name

      return username
    end),
    function()
      -- 失敗した場合はユーザーIDをそのまま返す
      return user_id
    end
  )
end

--- ユーザーIDからユーザー名を取得（コールバック版 - 後方互換性のため）
--- @param user_id string ユーザーID
--- @param callback function コールバック関数
--- @return nil
function M.get_username(user_id, callback)
  local promise = M.get_username_promise(user_id)

  utils.Promise.then_func(promise, function(username)
    vim.schedule(function()
      callback(username)
    end)
  end)
end

return M