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

return M