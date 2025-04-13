---@brief [[
--- neo-slack.nvim 設定管理モジュール
--- プラグインの設定を管理します
---@brief ]]

local utils = require('neo-slack.utils')
local events = require('neo-slack.core.events')

---@class NeoSlackConfig
local M = {}

-- デフォルト設定
M.defaults = {
  token = '',
  default_channel = 'general',
  refresh_interval = 30,
  notification = true,
  debug = false,
  auto_reconnect = true,
  reconnect_interval = 300, -- 5分
  auto_open_default_channel = true,
  layout = {
    type = 'split',  -- 'split', 'float', 'tab', 'telescope'
    channels = {
      width = 30,
      position = 'left',
    },
    messages = {
      width = 'auto',
      position = 'center',
    },
    thread = {
      width = 'auto',
      position = 'right',
    },
  },
  keymaps = {
    toggle = '<leader>ss',
    channels = '<leader>sc',
    messages = '<leader>sm',
    reply = '<leader>sr',
    react = '<leader>se',
  },
  initialization = {
    async = true,
    timeout = 30, -- 初期化タイムアウト（秒）
    retry = {
      enabled = true,
      max_attempts = 3,
      delay = 5, -- 再試行までの遅延（秒）
    }
  }
}

-- 現在の設定
M.current = vim.deepcopy(M.defaults)

--- 設定を初期化
--- @param opts table|nil ユーザー設定
--- @return table 最終的な設定
function M.setup(opts)
  opts = opts or {}
  
  -- ユーザー設定をデフォルト設定とマージ
  M.current = utils.deep_merge(vim.deepcopy(M.defaults), opts)
  
  -- Vimスクリプトからの設定を読み込み（Luaの設定が優先）
  M.load_from_vim_globals()
  
  -- 設定変更イベントを発行
  events.emit('config:updated', M.current)
  
  return M.current
end

--- Vimグローバル変数から設定を読み込み
function M.load_from_vim_globals()
  -- トークン
  if M.current.token == '' and vim.g.neo_slack_token then
    M.current.token = vim.g.neo_slack_token
  end
  
  -- デフォルトチャンネル
  if vim.g.neo_slack_default_channel then
    M.current.default_channel = vim.g.neo_slack_default_channel
  end
  
  -- 更新間隔
  if vim.g.neo_slack_refresh_interval then
    M.current.refresh_interval = vim.g.neo_slack_refresh_interval
  end
  
  -- 通知設定
  if vim.g.neo_slack_notification ~= nil then
    M.current.notification = vim.g.neo_slack_notification == 1
  end
  
  -- デバッグモード
  if vim.g.neo_slack_debug ~= nil then
    M.current.debug = vim.g.neo_slack_debug == 1
  end
  
  -- 自動再接続
  if vim.g.neo_slack_auto_reconnect ~= nil then
    M.current.auto_reconnect = vim.g.neo_slack_auto_reconnect == 1
  end
  
  -- 再接続間隔
  if vim.g.neo_slack_reconnect_interval then
    M.current.reconnect_interval = vim.g.neo_slack_reconnect_interval
  end
  
  -- デフォルトチャンネルの自動表示
  if vim.g.neo_slack_auto_open_default_channel ~= nil then
    M.current.auto_open_default_channel = vim.g.neo_slack_auto_open_default_channel == 1
  end
  
  -- キーマッピング
  if vim.g.neo_slack_keymaps then
    M.current.keymaps = vim.tbl_deep_extend('force', M.current.keymaps, vim.g.neo_slack_keymaps)
  end
  
  -- レイアウト
  if vim.g.neo_slack_layout then
    M.current.layout = vim.tbl_deep_extend('force', M.current.layout, vim.g.neo_slack_layout)
  end
  
  -- 初期化設定
  if vim.g.neo_slack_initialization then
    M.current.initialization = vim.tbl_deep_extend('force', M.current.initialization, vim.g.neo_slack_initialization)
  end
end

--- 設定値を取得
--- @param key string|nil 設定キー（nilの場合は全ての設定を返す）
--- @param default any|nil デフォルト値
--- @return any 設定値
function M.get(key, default)
  if key == nil then
    return M.current
  end
  
  -- ネストされたキーをサポート（例: 'layout.type'）
  local keys = {}
  for k in string.gmatch(key, '[^%.]+') do
    table.insert(keys, k)
  end
  
  return utils.get_nested(M.current, keys, default)
end

--- 設定値を更新
--- @param key string 設定キー
--- @param value any 設定値
function M.set(key, value)
  -- ネストされたキーをサポート（例: 'layout.type'）
  local keys = {}
  for k in string.gmatch(key, '[^%.]+') do
    table.insert(keys, k)
  end
  
  local current = M.current
  for i = 1, #keys - 1 do
    if type(current[keys[i]]) ~= 'table' then
      current[keys[i]] = {}
    end
    current = current[keys[i]]
  end
  
  -- 値を更新
  current[keys[#keys]] = value
  
  -- 設定変更イベントを発行
  events.emit('config:updated', key, value)
end

--- 設定をリセット
function M.reset()
  M.current = vim.deepcopy(M.defaults)
  events.emit('config:reset')
end

--- デバッグモードかどうかを取得
--- @return boolean デバッグモードかどうか
function M.is_debug()
  return M.current.debug
end

return M