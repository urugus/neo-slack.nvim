---@brief [[
--- neo-slack.nvim UI メッセージモジュール
--- メッセージ一覧の表示と操作を担当します
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_api() return dependency.get('api') end
local function get_utils() return dependency.get('utils') end
local function get_state() return dependency.get('state') end
local function get_events() return dependency.get('core.events') end
local function get_layout() return dependency.get('ui.layout') end

---@class NeoSlackUIMessages
local M = {}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
local function notify(message, level, opts)
  opts = opts or {}
  opts.prefix = 'UI Messages: '
  get_utils().notify(message, level, opts)
end

-- メッセージ一覧を表示
---@param channel string|nil チャンネル名またはID
---@param messages table[]|nil メッセージオブジェクトの配列
function M.show_messages(channel, messages)
  notify('UIにメッセージ一覧を表示します: channel=' .. tostring(channel) .. ', messages=' .. tostring(messages and #messages or 0) .. '件', vim.log.levels.INFO)

  local layout = get_layout()
  if not layout.layout.messages_buf or not vim.api.nvim_buf_is_valid(layout.layout.messages_buf) then
    notify('メッセージバッファが無効です', vim.log.levels.ERROR)
    return
  end

  -- チャンネル情報を取得
  local channel_id = channel
  local channel_name = channel

  -- チャンネルオブジェクトを検索
  for _, ch in ipairs(get_state().get_channels()) do
    if ch.id == channel or ch.name == channel then
      channel_id = ch.id
      channel_name = ch.name or ch.id
      break
    end
  end

  -- チャンネル名をウィンドウタイトルに設定
  if layout.layout.messages_win and vim.api.nvim_win_is_valid(layout.layout.messages_win) then
    vim.api.nvim_win_set_config(layout.layout.messages_win, {
      title = 'Messages: ' .. channel_name
    })
  end

  -- メッセージがない場合
  if not messages then
    notify('messagesがnilです', vim.log.levels.ERROR)
    vim.api.nvim_buf_set_option(layout.layout.messages_buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(layout.layout.messages_buf, 0, -1, false, {'メッセージがありません (nil)'})
    vim.api.nvim_buf_set_option(layout.layout.messages_buf, 'modifiable', false)
    return
  end

  if #messages == 0 then
    notify('messagesが空の配列です', vim.log.levels.INFO)
    vim.api.nvim_buf_set_option(layout.layout.messages_buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(layout.layout.messages_buf, 0, -1, false, {'メッセージがありません (空の配列)'})
    vim.api.nvim_buf_set_option(layout.layout.messages_buf, 'modifiable', false)
    return
  end

  notify('メッセージを表示します: ' .. #messages .. '件', vim.log.levels.INFO)

  -- メッセージを時系列順にソート
  table.sort(messages, function(a, b)
    return tonumber(a.ts) < tonumber(b.ts)
  end)

  -- バッファを編集可能に設定
  vim.api.nvim_buf_set_option(layout.layout.messages_buf, 'modifiable', true)

  -- バッファをクリア
  vim.api.nvim_buf_set_lines(layout.layout.messages_buf, 0, -1, false, {})

  -- 行とメッセージのマッピング
  local line_to_message = {}
  local current_line = 0

  -- ユーザー情報が更新されたときのイベントハンドラを登録
  local event_id = get_events().on('state:user_cache_updated', function(user_id, user_data)
    -- メッセージを再表示
    M.show_messages(channel, messages)
    -- イベントハンドラを削除（一度だけ実行）
    get_events().off('state:user_cache_updated', event_id)
  end)

  -- メッセージを表示
  for _, message in ipairs(messages) do
    -- メッセージの種類を判断
    local is_system_message = message.subtype ~= nil
    local header_prefix = ""

    -- ユーザー名を取得
    local user_name = "System"  -- デフォルトはシステムメッセージとして扱う

    -- 通常のユーザーメッセージの場合
    if not is_system_message and message.user then
      local user_id = message.user

      -- ユーザー名を取得（同期的に処理）
      user_name = "unknown"
      local user_data = get_state().get_user_by_id(user_id)
      if user_data then
        local display_name = user_data.profile.display_name
        local real_name = user_data.profile.real_name
        user_name = (display_name and display_name ~= '') and display_name or real_name
      end
    else
      -- システムメッセージの場合、subtypeに応じた表示にする
      if message.subtype == "channel_join" then
        header_prefix = "[参加] "
      elseif message.subtype == "channel_leave" then
        header_prefix = "[退出] "
      elseif message.subtype == "channel_topic" then
        header_prefix = "[トピック変更] "
      elseif message.subtype == "channel_purpose" then
        header_prefix = "[目的変更] "
      elseif message.subtype == "channel_name" then
        header_prefix = "[名前変更] "
      elseif message.subtype == "bot_message" then
        user_name = "Bot"
        if message.username then
          user_name = message.username
        end
      else
        header_prefix = "[" .. (message.subtype or "system") .. "] "
      end
    end

    -- タイムスタンプをフォーマット
    local timestamp = os.date("%Y-%m-%d %H:%M:%S", tonumber(message.ts))

    -- メッセージヘッダーを表示（ユーザー名とタイムスタンプ）
    local header = header_prefix .. user_name .. " (" .. timestamp .. ")"
    vim.api.nvim_buf_set_lines(layout.layout.messages_buf, current_line, current_line + 1, false, {header})
    line_to_message[current_line] = message
    current_line = current_line + 1

    -- メッセージ内容を表示
    local text = message.text or "(内容なし)"

    -- リッチテキスト形式のメッセージの場合、特殊な処理を行う
    if message.blocks then
      -- リッチテキストの内容を取得
      local rich_text = ""

      for _, block in ipairs(message.blocks) do
        -- タイプ1: block.type == "rich_text"の場合
        if block.type == "rich_text" and block.elements then
          for _, element in ipairs(block.elements) do
            if element.type == "rich_text_section" then
              for _, sub_element in ipairs(element.elements) do
                if sub_element.type == "text" then
                  rich_text = rich_text .. sub_element.text
                elseif sub_element.type == "user" then
                  rich_text = rich_text .. "@user"
                elseif sub_element.type == "usergroup" then
                  rich_text = rich_text .. "@group"
                elseif sub_element.type == "channel" then
                  rich_text = rich_text .. "#channel"
                elseif sub_element.type == "link" then
                  rich_text = rich_text .. sub_element.url
                end
              end
            end
          end
        -- タイプ2: block.textがオブジェクトの場合
        elseif block.text and type(block.text) == "table" and block.text.text then
          rich_text = rich_text .. block.text.text
        -- タイプ3: block.textが文字列の場合
        elseif block.text and type(block.text) == "string" then
          rich_text = rich_text .. block.text
        end
      end

      -- リッチテキストがある場合は、それを表示する
      if rich_text ~= "" then
        text = rich_text
      end
    end

    local lines = get_utils().split_lines(text)

    -- メッセージ行を追加
    for _, line in ipairs(lines) do
      vim.api.nvim_buf_set_lines(layout.layout.messages_buf, current_line, current_line + 1, false, {"  " .. line})
      line_to_message[current_line] = message
      current_line = current_line + 1
    end

    -- リアクションがある場合は表示
    if message.reactions and #message.reactions > 0 then
      local reactions_text = "  リアクション: "
      for i, reaction in ipairs(message.reactions) do
        reactions_text = reactions_text .. ":" .. reaction.name .. ": " .. reaction.count
        if i < #message.reactions then
          reactions_text = reactions_text .. ", "
        end
      end
      vim.api.nvim_buf_set_lines(layout.layout.messages_buf, current_line, current_line + 1, false, {reactions_text})
      line_to_message[current_line] = message
      current_line = current_line + 1
    end

    -- スレッドがある場合は表示
    if message.thread_ts and message.reply_count and message.reply_count > 0 then
      local thread_text = "  スレッド: " .. message.reply_count .. "件の返信"
      vim.api.nvim_buf_set_lines(layout.layout.messages_buf, current_line, current_line + 1, false, {thread_text})
      line_to_message[current_line] = message
      current_line = current_line + 1
    end

    -- 空行を追加
    vim.api.nvim_buf_set_lines(layout.layout.messages_buf, current_line, current_line + 1, false, {""})
    current_line = current_line + 1
  end

  -- バッファを編集不可に設定
  vim.api.nvim_buf_set_option(layout.layout.messages_buf, 'modifiable', false)

  -- 行とメッセージのマッピングを保存
  layout.layout.line_to_message = line_to_message

  -- メッセージ表示完了の通知
  notify('メッセージ表示が完了しました: ' .. current_line .. '行', vim.log.levels.INFO)

  -- メッセージウィンドウにフォーカス
  if layout.layout.messages_win and vim.api.nvim_win_is_valid(layout.layout.messages_win) then
    vim.api.nvim_set_current_win(layout.layout.messages_win)
  end
end

-- メッセージ一覧を更新
function M.refresh_messages()
  local channel_id = get_state().get_current_channel()
  if not channel_id then
    notify('現在のチャンネルが設定されていません', vim.log.levels.ERROR)
    return
  end

  get_api().get_messages(channel_id, function(success, messages)
    if success then
      M.show_messages(channel_id, messages)
    else
      notify('メッセージ一覧の更新に失敗しました', vim.log.levels.ERROR)
    end
  end)
end

-- メッセージを送信
function M.send_message()
  local channel_id = get_state().get_current_channel()
  if not channel_id then
    notify('現在のチャンネルが設定されていません', vim.log.levels.ERROR)
    return
  end

  -- 入力プロンプトを表示
  vim.ui.input({
    prompt = 'メッセージを入力: ',
  }, function(input)
    if not input or input == '' then
      return
    end

    -- メッセージを送信
    get_api().send_message(channel_id, input, function(success)
      if success then
        notify('メッセージを送信しました', vim.log.levels.INFO)
        -- メッセージ一覧を更新
        M.refresh_messages()
      else
        notify('メッセージの送信に失敗しました', vim.log.levels.ERROR)
      end
    end)
  end)
end

-- スレッドを表示
function M.show_thread()
  local layout = get_layout()
  if not layout.layout.messages_buf or not vim.api.nvim_buf_is_valid(layout.layout.messages_buf) then
    return
  end

  -- カーソル位置の行を取得
  local cursor = vim.api.nvim_win_get_cursor(layout.layout.messages_win)
  local line = cursor[1] - 1 -- 0-indexedに変換

  -- メッセージを取得
  local message = layout.layout.line_to_message and layout.layout.line_to_message[line]
  if not message then
    notify('この行にはメッセージがありません', vim.log.levels.WARN)
    return
  end

  -- スレッドのタイムスタンプを取得
  local thread_ts = message.thread_ts or message.ts
  if not thread_ts then
    notify('このメッセージにはスレッドがありません', vim.log.levels.WARN)
    return
  end

  -- 現在のチャンネルIDを取得
  local channel_id = get_state().get_current_channel()
  if not channel_id then
    notify('現在のチャンネルが設定されていません', vim.log.levels.ERROR)
    return
  end

  -- スレッド情報を保存
  get_state().set_current_thread(thread_ts, message)

  -- スレッド表示イベントを発行
  get_events().emit('thread_selected', channel_id, thread_ts)
end

-- リアクションを追加
function M.add_reaction()
  local layout = get_layout()
  if not layout.layout.messages_buf or not vim.api.nvim_buf_is_valid(layout.layout.messages_buf) then
    return
  end

  -- カーソル位置の行を取得
  local cursor = vim.api.nvim_win_get_cursor(layout.layout.messages_win)
  local line = cursor[1] - 1 -- 0-indexedに変換

  -- メッセージを取得
  local message = layout.layout.line_to_message and layout.layout.line_to_message[line]
  if not message then
    notify('この行にはメッセージがありません', vim.log.levels.WARN)
    return
  end

  -- 入力プロンプトを表示
  vim.ui.input({
    prompt = 'リアクション（絵文字名）を入力: ',
  }, function(input)
    if not input or input == '' then
      return
    end

    -- 現在のチャンネルIDを取得
    local channel_id = get_state().get_current_channel()
    if not channel_id then
      notify('現在のチャンネルが設定されていません', vim.log.levels.ERROR)
      return
    end

    -- リアクションを追加
    get_api().add_reaction(channel_id, message.ts, input, function(success)
      if success then
        notify('リアクションを追加しました: :' .. input .. ':', vim.log.levels.INFO)
        -- メッセージ一覧を更新
        M.refresh_messages()
      else
        notify('リアクションの追加に失敗しました', vim.log.levels.ERROR)
      end
    end)
  end)
end

return M