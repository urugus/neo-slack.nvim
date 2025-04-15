---@brief [[
--- neo-slack.nvim API リアクションモジュール
--- リアクションの追加と管理を行います
---@brief ]]

local utils = require('neo-slack.utils')
local api_utils = require('neo-slack.api.utils')
local events = require('neo-slack.core.events')

---@class NeoSlackAPIReactions
local M = {}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
---@return nil
local function notify(message, level, opts)
  api_utils.notify(message, level, opts)
end

-- APIコアモジュールへの参照を保持する変数
local core

-- APIコアモジュールを取得する関数
local function get_core()
  if not core then
    core = require('neo-slack.api.core')
  end
  return core
end

--- リアクションを追加（Promise版）
--- @param message_ts string メッセージのタイムスタンプ
--- @param emoji string 絵文字名
--- @param channel_id string|nil チャンネルID（nilの場合は現在のチャンネルを使用）
--- @return table Promise
function M.add_reaction_promise(message_ts, emoji, channel_id)
  return utils.Promise.new(function(resolve, reject)
    -- チャンネルIDが指定されていない場合は、イベントを発行して取得
    if not channel_id then
      -- 現在のチャンネルIDを取得するためのイベントを発行
      events.emit('api:get_current_channel')

      -- イベントハンドラを一度だけ登録
      events.once('api:current_channel', function(current_channel_id)
        if not current_channel_id then
          notify('現在のチャンネルIDが設定されていません。メッセージ一覧を表示してからリアクションを追加してください。', vim.log.levels.ERROR)
          reject({ error = 'チャンネルIDが設定されていません' })
          return
        end

        -- 取得したチャンネルIDで再帰的に呼び出し
        local promise = M.add_reaction_promise(message_ts, emoji, current_channel_id)
        utils.Promise.catch_func(
          utils.Promise.then_func(promise, resolve),
          reject
        )
      end)

      return
    end

    -- 絵文字名から「:」を削除
    emoji = emoji:gsub(':', '')

    local params = {
      channel = channel_id,
      timestamp = message_ts,
      name = emoji,
    }

    local request_promise = get_core().request_promise('POST', 'reactions.add', params)

    utils.Promise.catch_func(
      utils.Promise.then_func(request_promise, function(data)
        notify('リアクションを追加しました', vim.log.levels.INFO)

        -- リアクション追加イベントを発行
        events.emit('api:reaction_added', channel_id, message_ts, emoji, data)

        resolve(data)
      end),
      function(err)
        local error_msg = err.error or 'Unknown error'
        notify('リアクションの追加に失敗しました - ' .. error_msg, vim.log.levels.ERROR)

        -- リアクション追加失敗イベントを発行
        events.emit('api:reaction_added_failure', channel_id, message_ts, emoji, err)

        reject(err)
      end
    )
  end)
end

--- リアクションを追加（コールバック版 - 後方互換性のため）
--- @param message_ts string メッセージのタイムスタンプ
--- @param emoji string 絵文字名
--- @param callback function コールバック関数
--- @return nil
function M.add_reaction(message_ts, emoji, callback)
  local promise = M.add_reaction_promise(message_ts, emoji)
  utils.Promise.catch_func(
    utils.Promise.then_func(promise, function()
      vim.schedule(function()
        callback(true)
      end)
    end),
    function()
      vim.schedule(function()
        callback(false)
      end)
    end
  )
end

return M