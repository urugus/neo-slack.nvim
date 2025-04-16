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
    local instance = M.factories[name]()
    M.container[name] = instance
    return instance
  end

  -- 通常のrequireを試みる
  local success, module = pcall(require, 'neo-slack.' .. name)
  if success then
    M.container[name] = module
    return module
  end

  error('依存関係が見つかりません: ' .. name)
end

--- 全ての依存関係を初期化
---@return nil
function M.initialize()
  -- コアモジュールの登録
  M.register_factory('core.config', function() return require('neo-slack.core.config') end)
  M.register_factory('core.events', function() return require('neo-slack.core.events') end)
  M.register_factory('utils', function() return require('neo-slack.utils') end)
  M.register_factory('state', function() return require('neo-slack.state') end)
  M.register_factory('storage', function() return require('neo-slack.storage') end)

  -- APIモジュールの登録
  M.register_factory('api', function() return require('neo-slack.api.init') end)
  M.register_factory('api.core', function() return require('neo-slack.api.core') end)
  M.register_factory('api.utils', function() return require('neo-slack.api.utils') end)
  M.register_factory('api.channels', function() return require('neo-slack.api.channels') end)
  M.register_factory('api.messages', function() return require('neo-slack.api.messages') end)
  M.register_factory('api.reactions', function() return require('neo-slack.api.reactions') end)
  M.register_factory('api.files', function() return require('neo-slack.api.files') end)
  M.register_factory('api.users', function() return require('neo-slack.api.users') end)

  -- 機能モジュールの登録
  M.register_factory('ui', function() return require('neo-slack.ui') end)
  M.register_factory('notification', function() return require('neo-slack.notification') end)
end

return M