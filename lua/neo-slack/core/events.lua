---@brief [[
--- neo-slack.nvim イベントバスモジュール
--- モジュール間の通信を仲介し、循環参照を解消します
--- 改良版：型定義、名前空間、非同期処理のサポート
---@brief ]]

-- 依存性の取得
local dependency

---@class EventOptions
---@field async boolean|nil 非同期で実行するかどうか
---@field namespace string|nil イベントの名前空間
---@field log_level number|nil ログレベル

---@class EventSubscription
---@field event string イベント名
---@field callback function コールバック関数
---@field options EventOptions|nil オプション

---@class NeoSlackEvents
---@field listeners table イベントリスナーのテーブル
---@field namespaces table 名前空間のテーブル
---@field event_history table イベント履歴
---@field max_history_size number 履歴の最大サイズ
---@field debug boolean デバッグモード
local M = {
  listeners = {},
  namespaces = {},
  event_history = {},
  max_history_size = 100,
  debug = false
}

-- 依存性注入の初期化
local function init_dependencies()
  if not dependency then
    dependency = require('neo-slack.core.dependency')
  end
end

-- ログヘルパー関数
---@param message string ログメッセージ
---@param level number|nil ログレベル
local function log(message, level)
  init_dependencies()
  local utils = dependency.get('utils')
  utils.notify(message, level or vim.log.levels.DEBUG, { prefix = 'Events: ' })
end

--- イベントリスナーを登録
---@param event string イベント名
---@param callback function コールバック関数
---@param options EventOptions|nil オプション
---@return function 登録解除用の関数
function M.on(event, callback, options)
  options = options or {}

  -- 名前空間付きイベント名を生成
  local full_event = event
  if options.namespace then
    full_event = options.namespace .. ":" .. event
    -- 名前空間を記録
    M.namespaces[options.namespace] = M.namespaces[options.namespace] or {}
    table.insert(M.namespaces[options.namespace], event)
  end

  -- リスナーリストを初期化
  M.listeners[full_event] = M.listeners[full_event] or {}

  -- リスナー情報を作成
  local listener = {
    callback = callback,
    options = options
  }

  -- リスナーを追加
  table.insert(M.listeners[full_event], listener)

  if M.debug then
    log('リスナーを登録: ' .. full_event, vim.log.levels.DEBUG)
  end

  -- 登録解除用の関数を返す
  return function()
    for i, l in ipairs(M.listeners[full_event] or {}) do
      if l.callback == callback then
        table.remove(M.listeners[full_event], i)

        if M.debug then
          log('リスナーを解除: ' .. full_event, vim.log.levels.DEBUG)
        end

        break
      end
    end
  end
end

--- イベントを一度だけ処理するリスナーを登録
---@param event string イベント名
---@param callback function コールバック関数
---@param options EventOptions|nil オプション
---@return function 登録解除用の関数
function M.once(event, callback, options)
  options = options or {}

  local function one_time_callback(...)
    -- 登録解除関数を呼び出す（クロージャで保持）
    local unsubscribe

    -- 元のコールバックを呼び出す
    local result = callback(...)

    -- 登録解除（非同期の場合は後で行う）
    if unsubscribe then
      unsubscribe()
    end

    return result
  end

  -- 登録して登録解除関数を取得
  local unsubscribe = M.on(event, one_time_callback, options)

  return unsubscribe
end

--- イベントを発行
---@param event string イベント名
---@param ... any イベントデータ
function M.emit(event, ...)
  local args = {...}
  local full_events = {event}

  -- 名前空間付きイベントも検索
  for namespace, _ in pairs(M.namespaces) do
    table.insert(full_events, namespace .. ":" .. event)
  end

  -- イベント履歴に追加
  if #M.event_history >= M.max_history_size then
    table.remove(M.event_history, 1)
  end
  table.insert(M.event_history, {
    event = event,
    args = args,
    timestamp = os.time()
  })

  -- 全ての該当イベントに対して処理
  for _, full_event in ipairs(full_events) do
    if not M.listeners[full_event] then
      goto continue
    end

    if M.debug then
      log('イベント発行: ' .. full_event, vim.log.levels.DEBUG)
    end

    -- リスナーのコピーを作成（コールバック内でリスナーが変更される可能性があるため）
    local listeners_copy = vim.deepcopy(M.listeners[full_event])

    for _, listener in ipairs(listeners_copy) do
      local callback = listener.callback
      local options = listener.options or {}

      -- 非同期実行
      if options.async then
        vim.defer_fn(function()
          -- エラーハンドリング
          local success, err = pcall(callback, unpack(args))
          if not success then
            local log_level = options.log_level or vim.log.levels.ERROR
            log('非同期イベントハンドラでエラーが発生しました (' .. full_event .. '): ' .. tostring(err), log_level)
          end
        end, 0)
      else
        -- 同期実行
        local success, err = pcall(callback, unpack(args))
        if not success then
          local log_level = options.log_level or vim.log.levels.ERROR
          log('イベントハンドラでエラーが発生しました (' .. full_event .. '): ' .. tostring(err), log_level)
        end
      end
    end

    ::continue::
  end
end

--- 名前空間内の全てのイベントを発行
---@param namespace string 名前空間
---@param ... any イベントデータ
function M.emit_namespace(namespace, ...)
  if not M.namespaces[namespace] then
    return
  end

  for _, event in ipairs(M.namespaces[namespace]) do
    M.emit(namespace .. ":" .. event, ...)
  end
end

--- 全てのイベントリスナーを削除
---@param event string|nil 特定のイベント名（nilの場合は全てのイベント）
---@param namespace string|nil 特定の名前空間（nilの場合は全ての名前空間）
function M.clear(event, namespace)
  if event and namespace then
    -- 特定の名前空間の特定のイベントをクリア
    M.listeners[namespace .. ":" .. event] = {}
  elseif event then
    -- 特定のイベントをクリア（全ての名前空間を含む）
    M.listeners[event] = {}
    for ns, _ in pairs(M.namespaces) do
      M.listeners[ns .. ":" .. event] = {}
    end
  elseif namespace then
    -- 特定の名前空間の全てのイベントをクリア
    for _, event_name in ipairs(M.namespaces[namespace] or {}) do
      M.listeners[namespace .. ":" .. event_name] = {}
    end
    M.namespaces[namespace] = {}
  else
    -- 全てのイベントをクリア
    M.listeners = {}
    M.namespaces = {}
  end

  if M.debug then
    if event and namespace then
      log('イベントをクリア: ' .. namespace .. ":" .. event, vim.log.levels.DEBUG)
    elseif event then
      log('イベントをクリア: ' .. event, vim.log.levels.DEBUG)
    elseif namespace then
      log('名前空間をクリア: ' .. namespace, vim.log.levels.DEBUG)
    else
      log('全てのイベントをクリア', vim.log.levels.DEBUG)
    end
  end
end

--- デバッグモードを設定
---@param enabled boolean デバッグモードを有効にするかどうか
function M.set_debug(enabled)
  M.debug = enabled
  log('デバッグモード: ' .. (enabled and 'ON' or 'OFF'), vim.log.levels.INFO)
end

--- デバッグ用：登録されているイベントとリスナー数を取得
---@return table イベントとリスナー数の対応表
function M.get_stats()
  local stats = {
    events = {},
    namespaces = {},
    total_listeners = 0
  }

  for event, listeners in pairs(M.listeners) do
    stats.events[event] = #listeners
    stats.total_listeners = stats.total_listeners + #listeners
  end

  for namespace, events in pairs(M.namespaces) do
    stats.namespaces[namespace] = #events
  end

  return stats
end

--- イベント履歴を取得
---@param limit number|nil 取得する履歴の最大数
---@return table イベント履歴
function M.get_history(limit)
  limit = limit or M.max_history_size

  local history = {}
  local start_idx = math.max(1, #M.event_history - limit + 1)

  for i = start_idx, #M.event_history do
    table.insert(history, M.event_history[i])
  end

  return history
end

return M