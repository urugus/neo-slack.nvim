---@brief [[
--- neo-slack.nvim イベントバスモジュール
--- モジュール間の通信を仲介し、循環参照を解消します
---@brief ]]

---@class NeoSlackEvents
---@field listeners table イベントリスナーのテーブル
local M = {
  listeners = {}
}

--- イベントリスナーを登録
---@param event string イベント名
---@param callback function コールバック関数
---@return function 登録解除用の関数
function M.on(event, callback)
  M.listeners[event] = M.listeners[event] or {}
  table.insert(M.listeners[event], callback)
  
  -- 登録解除用の関数を返す
  return function()
    for i, cb in ipairs(M.listeners[event] or {}) do
      if cb == callback then
        table.remove(M.listeners[event], i)
        break
      end
    end
  end
end

--- イベントを一度だけ処理するリスナーを登録
---@param event string イベント名
---@param callback function コールバック関数
---@return function 登録解除用の関数
function M.once(event, callback)
  local function one_time_callback(...)
    -- 最初に自分自身を登録解除
    for i, cb in ipairs(M.listeners[event] or {}) do
      if cb == one_time_callback then
        table.remove(M.listeners[event], i)
        break
      end
    end
    
    -- 元のコールバックを呼び出す
    return callback(...)
  end
  
  return M.on(event, one_time_callback)
end

--- イベントを発行
---@param event string イベント名
---@param ... any イベントデータ
function M.emit(event, ...)
  if not M.listeners[event] then
    return
  end
  
  -- リスナーのコピーを作成（コールバック内でリスナーが変更される可能性があるため）
  local callbacks = vim.deepcopy(M.listeners[event])
  
  for _, callback in ipairs(callbacks) do
    -- エラーハンドリング
    local success, err = pcall(callback, ...)
    if not success then
      vim.notify('Neo-Slack: イベントハンドラでエラーが発生しました (' .. event .. '): ' .. tostring(err), vim.log.levels.ERROR)
    end
  end
end

--- 全てのイベントリスナーを削除
---@param event string|nil 特定のイベント名（nilの場合は全てのイベント）
function M.clear(event)
  if event then
    M.listeners[event] = {}
  else
    M.listeners = {}
  end
end

--- デバッグ用：登録されているイベントとリスナー数を取得
---@return table イベントとリスナー数の対応表
function M.get_stats()
  local stats = {}
  for event, listeners in pairs(M.listeners) do
    stats[event] = #listeners
  end
  return stats
end

return M