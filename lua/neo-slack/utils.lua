---@brief [[
--- neo-slack.nvim ユーティリティモジュール
--- 共通のヘルパー関数を提供します
---@brief ]]

---@class NeoSlackUtils
local M = {}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
function M.notify(message, level)
  vim.notify('Neo-Slack: ' .. message, level)
end

-- テキストを複数行に分割
---@param text string|nil テキスト
---@return string[] 行の配列
function M.split_lines(text)
  if not text or text == '' then
    return {'(内容なし)'}
  end
  
  -- 改行で分割
  local lines = {}
  for line in text:gmatch('[^\r\n]+') do
    table.insert(lines, line)
  end
  
  -- 空の場合
  if #lines == 0 then
    return {'(内容なし)'}
  end
  
  return lines
end

-- タイムスタンプをフォーマット
---@param ts string|number タイムスタンプ
---@param format string|nil フォーマット（デフォルト: '%Y-%m-%d %H:%M'）
---@return string フォーマットされた日時文字列
function M.format_timestamp(ts, format)
  format = format or '%Y-%m-%d %H:%M'
  local timestamp = tonumber(ts)
  if not timestamp then
    return '不明な日時'
  end
  return os.date(format, math.floor(timestamp))
end

-- テーブルの深いマージ
---@param target table ターゲットテーブル
---@param source table ソーステーブル
---@return table マージされたテーブル
function M.deep_merge(target, source)
  for k, v in pairs(source) do
    if type(v) == 'table' and type(target[k]) == 'table' then
      M.deep_merge(target[k], v)
    else
      target[k] = v
    end
  end
  return target
end

-- 安全なテーブルアクセス
---@param tbl table|nil テーブル
---@param keys string[] キーのリスト
---@param default any デフォルト値
---@return any 値またはデフォルト値
function M.get_nested(tbl, keys, default)
  local current = tbl
  for _, key in ipairs(keys) do
    if type(current) ~= 'table' or current[key] == nil then
      return default
    end
    current = current[key]
  end
  return current
end

return M