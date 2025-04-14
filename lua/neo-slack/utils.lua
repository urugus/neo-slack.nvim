---@brief [[
--- neo-slack.nvim ユーティリティモジュール
--- 共通のヘルパー関数を提供します
---@brief ]]

---@class NeoSlackUtils
local M = {}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション（title, icon など）
---@return nil
function M.notify(message, level, opts)
  opts = opts or {}
  local title = opts.title or 'Neo-Slack'
  local prefix = opts.prefix or ''
  
  -- プレフィックスが指定されていない場合は、タイトルをプレフィックスとして使用
  if prefix == '' then
    prefix = title .. ': '
  end
  
  -- vim.notifyの拡張機能があれば使用（nvim-notify等）
  if vim.notify and type(vim.notify) == 'function' then
    vim.notify(prefix .. message, level, {
      title = title,
      icon = opts.icon,
    })
  else
    -- フォールバック：標準のエコーメッセージ
    local msg_type = 'Info'
    if level == vim.log.levels.ERROR then
      msg_type = 'Error'
    elseif level == vim.log.levels.WARN then
      msg_type = 'Warning'
    end
    vim.api.nvim_echo({{prefix .. message, msg_type}}, true, {})
  end
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
-- 絵文字コードを実際の絵文字に変換
---@param emoji_code string 絵文字コード（例: ":smile:"）
---@return string 変換された絵文字または元のコード
function M.convert_emoji_code(emoji_code)
  -- 絵文字コードから名前を抽出（コロンを除去）
  local emoji_name = emoji_code:match('^:([^:]+):$')
  if not emoji_name then
    return emoji_code
  end

  -- 基本的な絵文字マッピング
  local emoji_map = {
    -- 顔文字
    ["smile"] = "😄",
    ["grinning"] = "😀",
    ["smiley"] = "😃",
    ["grin"] = "😁",
    ["laughing"] = "😆",
    ["sweat_smile"] = "😅",
    ["joy"] = "😂",
    ["rofl"] = "🤣",
    ["relaxed"] = "☺️",
    ["blush"] = "😊",
    ["innocent"] = "😇",
    ["slightly_smiling_face"] = "🙂",
    ["upside_down_face"] = "🙃",
    ["wink"] = "😉",
    ["relieved"] = "😌",
    ["heart_eyes"] = "😍",
    ["kissing_heart"] = "😘",
    ["kissing"] = "😗",
    ["kissing_smiling_eyes"] = "😙",
    ["kissing_closed_eyes"] = "😚",
    ["yum"] = "😋",
    ["stuck_out_tongue"] = "😛",
    ["stuck_out_tongue_winking_eye"] = "😜",
    ["stuck_out_tongue_closed_eyes"] = "😝",
    ["money_mouth_face"] = "🤑",
    ["hugs"] = "🤗",
    ["thinking"] = "🤔",
    
    -- 手のジェスチャー
    ["thumbsup"] = "👍",
    ["thumbsdown"] = "👎",
    ["ok_hand"] = "👌",
    ["clap"] = "👏",
    ["raised_hands"] = "🙌",
    ["pray"] = "🙏",
    
    -- 動物
    ["cat"] = "🐱",
    ["dog"] = "🐶",
    ["mouse"] = "🐭",
    ["hamster"] = "🐹",
    ["rabbit"] = "🐰",
    ["fox_face"] = "🦊",
    ["bear"] = "🐻",
    ["panda_face"] = "🐼",
    ["koala"] = "🐨",
    ["tiger"] = "🐯",
    ["lion"] = "🦁",
    ["cow"] = "🐮",
    ["pig"] = "🐷",
    ["frog"] = "🐸",
    ["monkey_face"] = "🐵",
    
    -- 記号
    ["heart"] = "❤️",
    ["yellow_heart"] = "💛",
    ["green_heart"] = "💚",
    ["blue_heart"] = "💙",
    ["purple_heart"] = "💜",
    ["black_heart"] = "🖤",
    ["broken_heart"] = "💔",
    ["fire"] = "🔥",
    ["star"] = "⭐",
    ["sparkles"] = "✨",
    
    -- カスタム絵文字
    ["うれしい"] = "😊",
    ["clap-nya"] = "👏",
    ["eranyanko"] = "😺",
    ["nekowaiwai"] = "😻",
    ["tokiwo_umu_nyanko"] = "🐱",
    
    -- 一般的なリアクション
    ["+1"] = "👍",
    ["-1"] = "👎",
    ["eyes"] = "👀",
    ["tada"] = "🎉",
    ["100"] = "💯",
    ["clown_face"] = "🤡",
    ["question"] = "❓",
    ["exclamation"] = "❗",
    ["warning"] = "⚠️",
    ["bulb"] = "💡",
    ["rocket"] = "🚀",
    ["boom"] = "💥",
    ["zap"] = "⚡",
    ["muscle"] = "💪",
    ["metal"] = "🤘",
    ["ok"] = "🆗",
    ["new"] = "🆕",
    ["cool"] = "🆒",
    ["sos"] = "🆘",
    ["white_check_mark"] = "✅",
    ["x"] = "❌",
    ["heavy_check_mark"] = "✔️",
    ["heavy_multiplication_x"] = "✖️",
    ["heavy_plus_sign"] = "➕",
    ["heavy_minus_sign"] = "➖",
    ["heavy_division_sign"] = "➗",
    ["repeat"] = "🔁",
    ["arrows_counterclockwise"] = "🔄",
    ["arrow_right"] = "➡️",
    ["arrow_left"] = "⬅️",
    ["arrow_up"] = "⬆️",
    ["arrow_down"] = "⬇️",
    ["black_large_square"] = "⬛",
    ["white_large_square"] = "⬜",
    ["red_circle"] = "🔴",
    ["large_blue_circle"] = "🔵",
    ["white_circle"] = "⚪",
    ["black_circle"] = "⚫",
    ["radio_button"] = "🔘",
    ["speech_balloon"] = "💬",
    ["thought_balloon"] = "💭",
    ["clock1"] = "🕐",
    ["clock2"] = "🕑",
    ["clock3"] = "🕒",
    ["clock4"] = "🕓",
    ["clock5"] = "🕔",
    ["clock6"] = "🕕",
    ["clock7"] = "🕖",
    ["clock8"] = "🕗",
    ["clock9"] = "🕘",
    ["clock10"] = "🕙",
    ["clock11"] = "🕚",
    ["clock12"] = "🕛",
  }

  -- vim-emojiプラグインが利用可能な場合はそちらも使用
  local has_emoji, emoji = pcall(require, 'emoji')
  if has_emoji and emoji.emoji[emoji_name] then
    return emoji.emoji[emoji_name]
  end

  return emoji_map[emoji_name] or emoji_code
end

-- リアクションを整形（絵文字 + カウント）
---@param reaction table リアクションオブジェクト
---@return string 整形されたリアクション文字列
function M.format_reaction(reaction)
  local emoji_code = ":" .. reaction.name .. ":"
  local emoji = M.convert_emoji_code(emoji_code)
  return emoji .. " " .. reaction.count
end

-- デバッグログ
---@param message string ログメッセージ
---@param level number|nil ログレベル（デフォルト: INFO）
---@return nil
function M.debug_log(message, level)
  -- 設定モジュールを直接参照すると循環参照になるため、
  -- グローバル変数またはvim.gから設定を取得
  local is_debug = vim.g.neo_slack_debug == 1 or false
  
  if is_debug then
    M.notify('[DEBUG] ' .. message, level or vim.log.levels.INFO)
  end
end

-- 非同期処理のためのシンプルなPromiseライクな実装
---@class Promise
---@field status string 'pending'|'fulfilled'|'rejected'
---@field value any 成功時の値
---@field reason any 失敗時の理由
---@field then function thenメソッド
---@field catch function catchメソッド
---@field finally function finallyメソッド
M.Promise = {}
M.Promise.__index = M.Promise

-- Promiseを作成
---@param executor function Promiseの処理を行う関数
---@return table Promise
function M.Promise.new(executor)
  local self = setmetatable({
    status = 'pending',
    value = nil,
    reason = nil,
    _on_fulfilled = {},
    _on_rejected = {},
    _on_finally = {}
  }, M.Promise)
  
  local function resolve(value)
    if self.status ~= 'pending' then return end
    self.status = 'fulfilled'
    self.value = value
    
    vim.schedule(function()
      for _, callback in ipairs(self._on_fulfilled) do
        callback(value)
      end
      for _, callback in ipairs(self._on_finally) do
        callback()
      end
    end)
  end
  
  local function reject(reason)
    if self.status ~= 'pending' then return end
    self.status = 'rejected'
    self.reason = reason
    
    vim.schedule(function()
      for _, callback in ipairs(self._on_rejected) do
        callback(reason)
      end
      for _, callback in ipairs(self._on_finally) do
        callback()
      end
    end)
  end
  
  local success, err = pcall(executor, resolve, reject)
  if not success then
    reject(err)
  end
  
  return self
end

-- thenメソッド（通常の関数として定義）
---@param self table Promise
---@param on_fulfilled function|nil 成功時のコールバック
---@param on_rejected function|nil 失敗時のコールバック
---@return table Promise
function M.Promise.then_func(self, on_fulfilled, on_rejected)
  local promise = M.Promise.new(function(resolve, reject)
    if on_fulfilled and type(on_fulfilled) == 'function' then
      table.insert(self._on_fulfilled, function(value)
        local success, result = pcall(on_fulfilled, value)
        if success then
          resolve(result)
        else
          reject(result)
        end
      end)
    else
      table.insert(self._on_fulfilled, resolve)
    end
    
    if on_rejected and type(on_rejected) == 'function' then
      table.insert(self._on_rejected, function(reason)
        local success, result = pcall(on_rejected, reason)
        if success then
          resolve(result)
        else
          reject(result)
        end
      end)
    else
      table.insert(self._on_rejected, reject)
    end
  end)
  
  -- 既に完了している場合は即時実行
  if self.status == 'fulfilled' and on_fulfilled then
    vim.schedule(function()
      local success, result = pcall(on_fulfilled, self.value)
      if success then
        promise.value = result
        promise.status = 'fulfilled'
      else
        promise.reason = result
        promise.status = 'rejected'
      end
    end)
  elseif self.status == 'rejected' and on_rejected then
    vim.schedule(function()
      local success, result = pcall(on_rejected, self.reason)
      if success then
        promise.value = result
        promise.status = 'fulfilled'
      else
        promise.reason = result
        promise.status = 'rejected'
      end
    end)
  end
  
  return promise
end

-- catchメソッド（通常の関数として定義）
---@param self table Promise
---@param on_rejected function 失敗時のコールバック
---@return table Promise
function M.Promise.catch_func(self, on_rejected)
  return M.Promise.then_func(self, nil, on_rejected)
end

-- finallyメソッド（通常の関数として定義）
---@param self table Promise
---@param on_finally function 最終処理のコールバック
---@return table Promise
function M.Promise.finally_func(self, on_finally)
  table.insert(self._on_finally, on_finally)
  return self
end

-- メタメソッドを使用して、オブジェクト指向の構文をサポート
M.Promise.__index = M.Promise

-- メソッドを直接テーブルに追加
M.Promise["then"] = function(self, ...)
  return M.Promise.then_func(self, ...)
end

M.Promise["catch"] = function(self, ...)
  return M.Promise.catch_func(self, ...)
end

M.Promise["finally"] = function(self, ...)
  return M.Promise.finally_func(self, ...)
end

-- 複数のPromiseが完了するのを待つ
---@param promises table Promiseの配列
---@return table Promise
function M.Promise.all(promises)
  return M.Promise.new(function(resolve, reject)
    if #promises == 0 then
      resolve({})
      return
    end
    
    local results = {}
    local completed = 0
    
    for i, promise in ipairs(promises) do
      -- 直接関数を呼び出す
      M.Promise.then_func(promise,
        function(value)
          results[i] = value
          completed = completed + 1
          if completed == #promises then
            resolve(results)
          end
        end,
        function(reason)
          reject(reason)
        end
      )
    end
  end)
end

-- タイムアウト付きのPromise
---@param promise table Promise
---@param timeout number タイムアウト時間（ミリ秒）
---@return table Promise
function M.Promise.timeout(promise, timeout)
  return M.Promise.new(function(resolve, reject)
    local timer = vim.loop.new_timer()
    
    timer:start(timeout, 0, function()
      timer:stop()
      timer:close()
      reject('Timeout after ' .. timeout .. 'ms')
    end)
    
    -- 直接関数を呼び出す
    M.Promise.then_func(promise,
      function(value)
        if timer then
          timer:stop()
          timer:close()
        end
        resolve(value)
      end,
      function(reason)
        if timer then
          timer:stop()
          timer:close()
        end
        reject(reason)
      end
    )
  end)
end

return M