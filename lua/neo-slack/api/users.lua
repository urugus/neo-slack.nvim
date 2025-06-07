---@brief [[
--- neo-slack.nvim API ユーザーモジュール
--- ユーザー情報の取得と管理を行います
--- 改良版：依存性注入パターンを活用
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_utils() return dependency.get('utils') end
local function get_api_utils() return dependency.get('api.utils') end
local function get_events() return dependency.get('core.events') end
local function get_api_core() return dependency.get('api.core') end

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
  get_api_utils().notify(message, level, opts)
end

-- この関数は不要になりました（依存性注入で置き換え）

--- ユーザー情報を取得（Promise版）
--- @return table Promise
function M.get_user_info_promise()
  local promise = get_api_core().request_promise('GET', 'users.identity', {})

  return get_utils().Promise.then_func(promise, function(data)
    -- ユーザー情報を保存
    get_api_core().config.user_info = data

    -- ユーザー情報取得イベントを発行
    get_events().emit('api:user_info_loaded', data)

    return data
  end)
end

--- ユーザー情報を取得（コールバック版 - 後方互換性のため）
--- @param callback function コールバック関数
--- @return nil
M.get_user_info = get_api_utils().create_callback_version(M.get_user_info_promise)

--- 特定のユーザーIDからユーザー情報を取得（Promise版）
--- @param user_id string ユーザーID
--- @return table Promise
function M.get_user_info_by_id_promise(user_id)
  -- キャッシュにユーザー情報があれば、それを返す
  if M.users_cache[user_id] then
    return get_utils().Promise.new(function(resolve)
      resolve(M.users_cache[user_id])
    end)
  end

  -- APIからユーザー情報を取得
  local params = {
    user = user_id
  }

  local promise = get_api_core().request_promise('GET', 'users.info', params)

  return get_utils().Promise.catch_func(
    get_utils().Promise.then_func(promise, function(data)
      -- キャッシュに保存
      M.users_cache[user_id] = data.user

      -- ユーザー情報取得イベントを発行
      get_events().emit('api:user_info_by_id_loaded', user_id, data.user)

      return data.user
    end),
    function(err)
      local error_msg = err.error or 'Unknown error'
      local notification = 'ユーザー情報の取得に失敗しました - ' .. error_msg
      
      -- missing_scope エラーの場合、必要なスコープ情報を追加
      if err.error == 'missing_scope' and err.context and err.context.needed_scope then
        notification = notification .. '\n必要なスコープ: ' .. err.context.needed_scope
      end
      
      notify(notification, vim.log.levels.WARN)
      return get_utils().Promise.reject(err)
    end
  )
end

--- 特定のユーザーIDからユーザー情報を取得（コールバック版 - 後方互換性のため）
--- @param user_id string ユーザーID
--- @param callback function コールバック関数
--- @return nil
M.get_user_info_by_id = get_api_utils().create_callback_version(M.get_user_info_by_id_promise)

--- ユーザーIDからユーザー名を取得（Promise版）
--- @param user_id string ユーザーID
--- @return table Promise
function M.get_username_promise(user_id)
  local promise = M.get_user_info_by_id_promise(user_id)

  return get_utils().Promise.catch_func(
    get_utils().Promise.then_func(promise, function(user_data)
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

  get_utils().Promise.then_func(promise, function(username)
    vim.schedule(function()
      callback(username)
    end)
  end)
end

return M