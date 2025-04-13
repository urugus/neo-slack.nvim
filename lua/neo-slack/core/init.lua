---@brief [[
--- neo-slack.nvim コアモジュール
--- プラグイン全体の設定と初期化を担当します
---@brief ]]

local events = require('neo-slack.core.events')
local utils = require('neo-slack.utils')

---@class NeoSlackCore
---@field config NeoSlackConfig 設定オブジェクト
---@field events NeoSlackEvents イベントバス
local M = {}

-- イベントバスをエクスポート
M.events = events

-- デフォルト設定
---@class NeoSlackConfig
---@field token string Slack APIトークン
---@field default_channel string デフォルトチャンネル
---@field refresh_interval number 更新間隔（秒）
---@field notification boolean 通知の有効/無効
---@field debug boolean デバッグモード
---@field layout table レイアウト設定
---@field keymaps table キーマッピング設定
M.config = {
  token = '',
  default_channel = 'general',
  refresh_interval = 30,
  notification = true,
  debug = false,
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
  }
}

-- 初期化状態
M.initialized = false

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
local function notify(message, level)
  utils.notify(message, level)
end

--- プラグインの初期化
--- @param opts table|nil 設定オプション
--- @return boolean 初期化に成功したかどうか
function M.setup(opts)
  opts = opts or {}
  M.config = utils.deep_merge(M.config, opts)
  
  -- Vimスクリプトから設定を取得（Luaの設定が優先）
  if M.config.token == '' and vim.g.neo_slack_token then
    M.config.token = vim.g.neo_slack_token
  end
  
  if vim.g.neo_slack_default_channel then
    M.config.default_channel = vim.g.neo_slack_default_channel
  end
  
  if vim.g.neo_slack_refresh_interval then
    M.config.refresh_interval = vim.g.neo_slack_refresh_interval
  end
  
  if vim.g.neo_slack_notification ~= nil then
    M.config.notification = vim.g.neo_slack_notification == 1
  end
  
  if vim.g.neo_slack_debug ~= nil then
    M.config.debug = vim.g.neo_slack_debug == 1
  end
  
  -- 初期化イベントを発行
  events.emit('core:before_init', M.config)
  
  -- 初期化状態を設定
  M.initialized = true
  
  -- 初期化完了イベントを発行
  events.emit('core:after_init', M.config)
  
  notify('コアモジュールの初期化が完了しました', vim.log.levels.INFO)
  
  if M.config.debug then
    notify('デバッグモードが有効です', vim.log.levels.INFO)
  end
  
  return true
end

--- 設定を取得
--- @param key string|nil 設定キー（nilの場合は全ての設定を返す）
--- @param default any|nil デフォルト値
--- @return any 設定値
function M.get_config(key, default)
  if key == nil then
    return M.config
  end
  
  -- ネストされたキーをサポート（例: 'layout.type'）
  local keys = {}
  for k in string.gmatch(key, '[^%.]+') do
    table.insert(keys, k)
  end
  
  return utils.get_nested(M.config, keys, default)
end

--- 設定を更新
--- @param key string 設定キー
--- @param value any 設定値
function M.set_config(key, value)
  -- ネストされたキーをサポート（例: 'layout.type'）
  local keys = {}
  for k in string.gmatch(key, '[^%.]+') do
    table.insert(keys, k)
  end
  
  local current = M.config
  for i = 1, #keys - 1 do
    if type(current[keys[i]]) ~= 'table' then
      current[keys[i]] = {}
    end
    current = current[keys[i]]
  end
  
  current[keys[#keys]] = value
  
  -- 設定変更イベントを発行
  events.emit('core:config_changed', key, value)
end

--- 初期化状態を取得
--- @return boolean 初期化されているかどうか
function M.is_initialized()
  return M.initialized
end

return M