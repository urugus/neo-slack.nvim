---@brief [[
--- neo-slack.nvim エラーハンドリングモジュール
--- 統一されたエラーハンドリングを提供します
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_utils() return dependency.get('utils') end

---@class NeoSlackErrors
---@field error_types table エラータイプの定義
local M = {}

-- エラータイプの定義
M.error_types = {
  API = 'api_error',           -- APIエラー
  NETWORK = 'network_error',   -- ネットワークエラー
  CONFIG = 'config_error',     -- 設定エラー
  AUTH = 'auth_error',         -- 認証エラー
  STORAGE = 'storage_error',   -- ストレージエラー
  INTERNAL = 'internal_error', -- 内部エラー
  UI = 'ui_error',             -- UIエラー
  UNKNOWN = 'unknown_error',   -- 不明なエラー
}

-- エラーレベルのマッピング
M.level_map = {
  [M.error_types.API] = vim.log.levels.ERROR,
  [M.error_types.NETWORK] = vim.log.levels.ERROR,
  [M.error_types.CONFIG] = vim.log.levels.ERROR,
  [M.error_types.AUTH] = vim.log.levels.ERROR,
  [M.error_types.STORAGE] = vim.log.levels.ERROR,
  [M.error_types.INTERNAL] = vim.log.levels.ERROR,
  [M.error_types.UI] = vim.log.levels.WARN,
  [M.error_types.UNKNOWN] = vim.log.levels.ERROR,
}

-- エラーオブジェクトを作成
---@param type string エラータイプ
---@param message string エラーメッセージ
---@param details table|nil 追加の詳細情報
---@return table エラーオブジェクト
function M.create_error(type, message, details)
  return {
    type = type or M.error_types.UNKNOWN,
    message = message or 'Unknown error',
    details = details or {},
    timestamp = os.time(),
  }
end

-- エラーを処理（ログ記録と通知）
---@param err table|string エラーオブジェクトまたはエラーメッセージ
---@param type string|nil エラータイプ（エラーメッセージの場合のみ必要）
---@param details table|nil 追加の詳細情報（エラーメッセージの場合のみ必要）
---@param level number|nil 通知レベル（省略時はエラータイプに基づく）
---@param opts table|nil 通知オプション
---@return table 処理されたエラーオブジェクト
function M.handle_error(err, type, details, level, opts)
  -- エラーオブジェクトを作成または変換
  local error_obj
  if type(err) == 'string' then
    error_obj = M.create_error(type or M.error_types.UNKNOWN, err, details)
  elseif type(err) == 'table' and err.type and err.message then
    error_obj = err
  else
    error_obj = M.create_error(M.error_types.UNKNOWN, tostring(err), details)
  end

  -- エラーレベルを決定
  local log_level = level or M.level_map[error_obj.type] or vim.log.levels.ERROR

  -- 通知オプションを設定
  opts = opts or {}
  opts.prefix = opts.prefix or 'Error: '

  -- エラーを通知
  get_utils().notify(error_obj.message, log_level, opts)

  -- エラーオブジェクトを返す
  return error_obj
end

-- 関数実行を安全に行い、エラーをハンドリング
---@param func function 実行する関数
---@param error_type string|nil エラー発生時のエラータイプ
---@param error_prefix string|nil エラーメッセージのプレフィックス
---@param notify boolean|nil エラーを通知するかどうか（デフォルト: true）
---@return boolean success 成功したかどうか
---@return any result_or_error 結果またはエラーオブジェクト
function M.safe_call(func, error_type, error_prefix, notify)
  if notify == nil then notify = true end

  local success, result = pcall(func)

  if not success then
    local message = error_prefix and (error_prefix .. ': ' .. tostring(result)) or tostring(result)
    local error_obj = M.create_error(error_type or M.error_types.INTERNAL, message)

    if notify then
      M.handle_error(error_obj)
    end

    return false, error_obj
  end

  return true, result
end

-- Promiseのエラーハンドリングを統一
---@param promise table Promise
---@param error_type string|nil エラー発生時のエラータイプ
---@param error_prefix string|nil エラーメッセージのプレフィックス
---@param notify boolean|nil エラーを通知するかどうか（デフォルト: true）
---@return table Promise
function M.handle_promise(promise, error_type, error_prefix, notify)
  if notify == nil then notify = true end

  return get_utils().Promise.catch_func(promise, function(err)
    local message = error_prefix and (error_prefix .. ': ' .. tostring(err)) or tostring(err)
    local error_obj = M.create_error(error_type or M.error_types.UNKNOWN, message, { original_error = err })

    if notify then
      M.handle_error(error_obj)
    end

    return get_utils().Promise.reject(error_obj)
  end)
end

-- エラーを依存性注入コンテナに登録
dependency.register('core.errors', M)

return M