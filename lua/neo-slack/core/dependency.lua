---@brief [[
--- neo-slack.nvim 依存性注入モジュール
--- モジュール間の依存関係を管理し、循環参照を解消します
---@brief ]]

---@class NeoSlackDependency
---@field container table 依存関係のコンテナ
---@field factories table ファクトリー関数のテーブル
local M = {
  container = {},
  factories = {},
}

--- 依存関係を登録
---@param name string モジュール名
---@param instance any モジュールのインスタンス
---@return nil
function M.register(name, instance)
  M.container[name] = instance
end

--- ファクトリー関数を登録
---@param name string モジュール名
---@param factory function モジュールを生成するファクトリー関数
---@return nil
function M.register_factory(name, factory)
  M.factories[name] = factory
end

--- 依存関係を取得
---@param name string モジュール名
---@return any モジュールのインスタンス
function M.get(name)
  -- すでにインスタンス化されている場合はそれを返す
  if M.container[name] then
    return M.container[name]
  end

  -- ファクトリー関数が登録されている場合は実行してインスタンスを生成
  if M.factories[name] then
    local success, instance_or_error = pcall(M.factories[name])
    if success then
      M.container[name] = instance_or_error
      return instance_or_error
    else
      -- エラーハンドリング（core.errorsモジュールがまだ利用できない可能性があるため、基本的なエラー処理を行う）
      local error_message = '依存関係の初期化に失敗しました: ' .. name .. ' - ' .. tostring(instance_or_error)
      vim.notify(error_message, vim.log.levels.ERROR, { title = 'Dependency Error' })
      error(error_message)
    end
  end

  -- 通常のrequireを試みる
  local success, module_or_error = pcall(require, 'neo-slack.' .. name)
  if success then
    M.container[name] = module_or_error
    return module_or_error
  end

  -- エラーハンドリング
  local error_message = '依存関係が見つかりません: ' .. name .. ' - ' .. tostring(module_or_error)
  vim.notify(error_message, vim.log.levels.ERROR, { title = 'Dependency Error' })
  error(error_message)
end

--- 全ての依存関係を初期化
---@return boolean 初期化に成功したかどうか
function M.initialize()
  local success = true

  -- 初期化関数
  local function init_module(name, module_path)
    local ok, result = pcall(function()
      M.register_factory(name, function() return require(module_path) end)
    end)

    if not ok then
      vim.notify('モジュールの登録に失敗しました: ' .. name .. ' - ' .. tostring(result), vim.log.levels.ERROR)
      success = false
    end

    return ok
  end

  -- コアモジュールの登録
  init_module('core.config', 'neo-slack.core.config')
  init_module('core.events', 'neo-slack.core.events')
  init_module('core.errors', 'neo-slack.core.errors')
  init_module('utils', 'neo-slack.utils')
  init_module('state', 'neo-slack.state')
  init_module('storage', 'neo-slack.storage')

  -- APIモジュールの登録
  init_module('api', 'neo-slack.api.init')
  init_module('api.core', 'neo-slack.api.core')
  init_module('api.utils', 'neo-slack.api.utils')
  init_module('api.channels', 'neo-slack.api.channels')
  init_module('api.messages', 'neo-slack.api.messages')
  init_module('api.reactions', 'neo-slack.api.reactions')
  init_module('api.files', 'neo-slack.api.files')
  init_module('api.users', 'neo-slack.api.users')

  -- 機能モジュールの登録
  init_module('ui', 'neo-slack.ui')
  init_module('notification', 'neo-slack.notification')

  return success
end

return M