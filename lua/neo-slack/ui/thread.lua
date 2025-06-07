---@brief [[
--- neo-slack.nvim UI スレッドモジュール
--- スレッド表示の操作を担当します
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_api() return dependency.get('api') end
local function get_utils() return dependency.get('utils') end
local function get_state() return dependency.get('state') end
local function get_events() return dependency.get('core.events') end
local function get_layout() return dependency.get('ui.layout') end

---@class NeoSlackUIThread
local M = {}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
local function notify(message, level, opts)
  opts = opts or {}
  opts.prefix = 'UI Thread: '
  get_utils().notify(message, level, opts)
end

-- スレッド表示を初期化
function M.init_thread_window()
  local layout = get_layout()

  -- レイアウトを計算
  local layout_info = layout.calculate_layout()
  if not layout_info then
    notify('レイアウトの計算に失敗しました', vim.log.levels.ERROR)
    return
  end

  -- スレッドバッファが既に存在する場合は閉じる
  if layout.layout.thread_buf and vim.api.nvim_buf_is_valid(layout.layout.thread_buf) then
    vim.api.nvim_buf_delete(layout.layout.thread_buf, { force = true })
    layout.layout.thread_buf = nil
  end

  -- スレッドウィンドウが既に存在する場合は閉じる
  if layout.layout.thread_win and vim.api.nvim_win_is_valid(layout.layout.thread_win) then
    vim.api.nvim_win_close(layout.layout.thread_win, true)
    layout.layout.thread_win = nil
  end

  -- スレッドバッファを作成
  layout.layout.thread_buf = layout.create_buffer('Neo-Slack-Thread', 'neo-slack-messages', false)

  -- スレッドウィンドウを作成
  layout.layout.thread_win = layout.create_window(
    layout.layout.thread_buf,
    layout_info.messages_width, -- メッセージ一覧と同じ幅を使用
    layout_info.height,
    2,
    layout_info.channels_width + layout_info.messages_width + 6,
    'single',
    'Thread'
  )

  -- キーマッピングを設定
  M.setup_thread_keymaps()
end

-- スレッド表示のキーマッピングを設定
function M.setup_thread_keymaps()
  local layout = get_layout()
  if not layout.layout.thread_buf or not vim.api.nvim_buf_is_valid(layout.layout.thread_buf) then
    return
  end

  local opts = { noremap = true, silent = true }

  -- r: スレッドを更新
  vim.api.nvim_buf_set_keymap(layout.layout.thread_buf, 'n', 'r', [[<cmd>lua require('neo-slack.ui.thread').refresh_thread()<CR>]], opts)

  -- m: スレッドに返信
  vim.api.nvim_buf_set_keymap(layout.layout.thread_buf, 'n', 'm', [[<cmd>lua require('neo-slack.ui.thread').reply_to_thread()<CR>]], opts)

  -- a: リアクションを追加
  vim.api.nvim_buf_set_keymap(layout.layout.thread_buf, 'n', 'a', [[<cmd>lua require('neo-slack.ui.thread').add_reaction_to_thread()<CR>]], opts)

  -- q: スレッド表示を閉じる
  vim.api.nvim_buf_set_keymap(layout.layout.thread_buf, 'n', 'q', [[<cmd>lua require('neo-slack.ui.thread').close_thread()<CR>]], opts)
end

-- スレッドを表示
---@param channel_id string チャンネルID
---@param thread_ts string スレッドのタイムスタンプ
---@param replies table[]|nil 返信メッセージの配列
---@param parent_message table|nil 親メッセージ
function M.show_thread(channel_id, thread_ts, replies, parent_message)
  local layout = get_layout()




  -- スレッドウィンドウが存在しない場合は初期化
  if not layout.layout.thread_win or not vim.api.nvim_win_is_valid(layout.layout.thread_win) then
    M.init_thread_window()
  end

  if not layout.layout.thread_buf or not vim.api.nvim_buf_is_valid(layout.layout.thread_buf) then
    notify('スレッドバッファが無効です', vim.log.levels.ERROR)
    return
  end

  -- スレッド情報を取得
  local thread_info = get_state().get_current_thread()
  if not thread_info then
    notify('現在のスレッドが設定されていません', vim.log.levels.ERROR)
    return
  end


  -- ウィンドウタイトルを設定
  if layout.layout.thread_win and vim.api.nvim_win_is_valid(layout.layout.thread_win) then
    vim.api.nvim_win_set_config(layout.layout.thread_win, {
      title = 'Thread: ' .. os.date("%Y-%m-%d %H:%M:%S", tonumber(thread_ts))
    })
  end

  -- 返信がない場合
  if not replies or (type(replies) == "table" and #replies == 0) then
    -- バッファを編集可能に設定
    vim.api.nvim_buf_set_option(layout.layout.thread_buf, 'modifiable', true)

    -- バッファをクリア
    vim.api.nvim_buf_set_lines(layout.layout.thread_buf, 0, -1, false, {})

    -- 行とメッセージのマッピング
    local line_to_message = {}
    local current_line = 0

    -- parent_messageの処理は続行（親メッセージは表示する）
    -- この後の親メッセージ表示コードが実行される

    -- 返信がないメッセージを表示
    vim.api.nvim_buf_set_lines(layout.layout.thread_buf, current_line, current_line + 1, false, {'このスレッドには返信がありません'})
    current_line = current_line + 1

    -- バッファを編集不可に設定
    vim.api.nvim_buf_set_option(layout.layout.thread_buf, 'modifiable', false)

    -- 行とメッセージのマッピングを保存
    layout.layout.line_to_thread_message = line_to_message

    -- スレッドウィンドウにフォーカス
    if layout.layout.thread_win and vim.api.nvim_win_is_valid(layout.layout.thread_win) then
      vim.api.nvim_set_current_win(layout.layout.thread_win)
    end

    return
  end

  -- バッファを編集可能に設定
  vim.api.nvim_buf_set_option(layout.layout.thread_buf, 'modifiable', true)

  -- バッファをクリア
  vim.api.nvim_buf_set_lines(layout.layout.thread_buf, 0, -1, false, {})

  -- 行とメッセージのマッピング
  local line_to_message = {}
  local current_line = 0

  -- 親メッセージを表示
  if parent_message then
    -- ユーザー名を取得
    local user_name = "unknown"
    if parent_message.user then
      local user_data = get_state().get_user_by_id(parent_message.user)
      if user_data then
        local display_name = user_data.profile.display_name
        local real_name = user_data.profile.real_name
        user_name = (display_name and display_name ~= '') and display_name or real_name
      end
    elseif parent_message.username then
      user_name = parent_message.username
    end

    -- タイムスタンプをフォーマット
    local timestamp = os.date("%Y-%m-%d %H:%M:%S", tonumber(parent_message.ts))

    -- 親メッセージヘッダーを表示（強調表示）
    local header = "【親メッセージ】 " .. user_name .. " (" .. timestamp .. ")"
    vim.api.nvim_buf_set_lines(layout.layout.thread_buf, current_line, current_line + 1, false, {header})
    line_to_message[current_line] = parent_message
    current_line = current_line + 1

    -- 親メッセージ内容を表示
    local text = parent_message.text or "(内容なし)"
    local lines = get_utils().split_lines(text)

    for _, line in ipairs(lines) do
      vim.api.nvim_buf_set_lines(layout.layout.thread_buf, current_line, current_line + 1, false, {"  " .. line})
      line_to_message[current_line] = parent_message
      current_line = current_line + 1
    end

    -- 空行を追加
    vim.api.nvim_buf_set_lines(layout.layout.thread_buf, current_line, current_line + 1, false, {""})
    current_line = current_line + 1
  else
    -- parent_messageがnilの場合、thread_infoから情報を取得
    local thread_info = get_state().get_current_thread()
    if thread_info and type(thread_info) == "table" and thread_info.ts then
      -- タイムスタンプをフォーマット
      local timestamp = os.date("%Y-%m-%d %H:%M:%S", tonumber(thread_info.ts))

      -- 親メッセージヘッダーを表示
      local header = "【親メッセージ】 (元のメッセージを取得できませんでした) (" .. timestamp .. ")"
      vim.api.nvim_buf_set_lines(layout.layout.thread_buf, current_line, current_line + 1, false, {header})
      current_line = current_line + 1

      -- 空行を追加
      vim.api.nvim_buf_set_lines(layout.layout.thread_buf, current_line, current_line + 1, false, {""})
      current_line = current_line + 1
    else
      -- thread_infoがない場合
      vim.api.nvim_buf_set_lines(layout.layout.thread_buf, current_line, current_line + 1, false, {"【親メッセージ】 (元のメッセージを取得できませんでした)"})
      current_line = current_line + 1

      -- 空行を追加
      vim.api.nvim_buf_set_lines(layout.layout.thread_buf, current_line, current_line + 1, false, {""})
      current_line = current_line + 1
    end
  end

  -- 返信メッセージを表示
  for _, message in ipairs(replies) do
    -- ユーザー名を取得
    local user_name = "unknown"
    if message.user then
      local user_data = get_state().get_user_by_id(message.user)
      if user_data then
        local display_name = user_data.profile.display_name
        local real_name = user_data.profile.real_name
        user_name = (display_name and display_name ~= '') and display_name or real_name
      end
    elseif message.username then
      user_name = message.username
    end

    -- タイムスタンプをフォーマット
    local timestamp = os.date("%Y-%m-%d %H:%M:%S", tonumber(message.ts))

    -- メッセージヘッダーを表示
    local header
    if message.subtype then
      -- システムメッセージの場合は角括弧付きで表示
      local prefix = ""
      if message.subtype == "channel_join" then
        prefix = "[参加] "
      elseif message.subtype == "channel_leave" then
        prefix = "[退出] "
      elseif message.subtype == "channel_topic" then
        prefix = "[トピック変更] "
      elseif message.subtype == "channel_purpose" then
        prefix = "[目的変更] "
      elseif message.subtype == "channel_name" then
        prefix = "[名前変更] "
      elseif message.subtype == "bot_message" then
        prefix = "[Bot] "
      else
        prefix = "[" .. message.subtype .. "] "
      end
      header = prefix .. user_name .. " (" .. timestamp .. ")"
    else
      -- 通常のユーザーメッセージ
      header = user_name .. " (" .. timestamp .. ")"
    end
    vim.api.nvim_buf_set_lines(layout.layout.thread_buf, current_line, current_line + 1, false, {header})
    line_to_message[current_line] = message
    current_line = current_line + 1

    -- メッセージ内容を表示
    local text = message.text or "(内容なし)"
    local lines = get_utils().split_lines(text)

    for _, line in ipairs(lines) do
      vim.api.nvim_buf_set_lines(layout.layout.thread_buf, current_line, current_line + 1, false, {"  " .. line})
      line_to_message[current_line] = message
      current_line = current_line + 1
    end

    -- リアクションがある場合は表示
    if message.reactions and #message.reactions > 0 then
      local reactions_text = "  👍 リアクション: "
      for i, reaction in ipairs(message.reactions) do
        reactions_text = reactions_text .. ":" .. reaction.name .. ": " .. reaction.count
        if i < #message.reactions then
          reactions_text = reactions_text .. ", "
        end
      end
      vim.api.nvim_buf_set_lines(layout.layout.thread_buf, current_line, current_line + 1, false, {reactions_text})
      line_to_message[current_line] = message
      current_line = current_line + 1
    end

    -- 空行を追加
    vim.api.nvim_buf_set_lines(layout.layout.thread_buf, current_line, current_line + 1, false, {""})
    current_line = current_line + 1
  end

  -- バッファを編集不可に設定
  vim.api.nvim_buf_set_option(layout.layout.thread_buf, 'modifiable', false)

  -- 行とメッセージのマッピングを保存
  layout.layout.line_to_thread_message = line_to_message

  -- スレッドウィンドウにフォーカス
  if layout.layout.thread_win and vim.api.nvim_win_is_valid(layout.layout.thread_win) then
    vim.api.nvim_set_current_win(layout.layout.thread_win)

    -- カーソル移動時のハイライト更新のためのオートコマンドを設定
    vim.cmd([[
      augroup neo_slack_thread_highlight
        autocmd!
        autocmd CursorMoved <buffer> lua require('neo-slack.ui.thread').highlight_current_message()
      augroup END
    ]])

    -- 初期状態でカーソル位置のメッセージをハイライト
    M.highlight_current_message()
  end
end

-- 現在選択中のメッセージをハイライト
function M.highlight_current_message()
  local layout = get_layout()
  if not layout.layout.thread_buf or not vim.api.nvim_buf_is_valid(layout.layout.thread_buf) then
    return
  end

  -- 既存のハイライトをクリア
  vim.api.nvim_buf_clear_namespace(layout.layout.thread_buf, -1, 0, -1)

  -- カーソル位置の行を取得
  local cursor = vim.api.nvim_win_get_cursor(layout.layout.thread_win)
  local line = cursor[1] - 1 -- 0-indexedに変換

  -- メッセージを取得
  local message = layout.layout.line_to_thread_message and layout.layout.line_to_thread_message[line]
  if not message then
    return
  end

  -- メッセージに関連するすべての行をハイライト
  for l, msg in pairs(layout.layout.line_to_thread_message) do
    if msg.ts == message.ts then
      -- 行をハイライト
      vim.api.nvim_buf_add_highlight(layout.layout.thread_buf, -1, 'NeoSlackCurrentMessage', l, 0, -1)
    end
  end
end

-- スレッドを更新
function M.refresh_thread()
  -- スレッド情報を取得
  local thread_info = get_state().get_current_thread()
  if not thread_info then
    notify('現在のスレッドが設定されていません', vim.log.levels.ERROR)
    return
  end

  -- 現在のチャンネルIDを取得
  local channel_id = get_state().get_current_channel()
  if not channel_id then
    notify('現在のチャンネルが設定されていません', vim.log.levels.ERROR)
    return
  end

  -- スレッド返信を取得
  get_api().get_thread_replies(channel_id, thread_info.ts, function(success, replies, parent_message)
    if success then
      -- スレッド返信を保存
      get_state().set_thread_messages(replies)
      -- スレッドを表示
      M.show_thread(channel_id, thread_info.ts, replies, parent_message)
    else
      notify('スレッド返信の取得に失敗しました', vim.log.levels.ERROR)
    end
  end)
end

-- スレッドに返信
function M.reply_to_thread()
  -- スレッド情報を取得
  local thread_info = get_state().get_current_thread()
  if not thread_info then
    notify('現在のスレッドが設定されていません', vim.log.levels.ERROR)
    return
  end

  -- 現在のチャンネルIDを取得
  local channel_id = get_state().get_current_channel()
  if not channel_id then
    notify('現在のチャンネルが設定されていません', vim.log.levels.ERROR)
    return
  end

  -- 入力プロンプトを表示
  vim.ui.input({
    prompt = 'スレッド返信を入力: ',
  }, function(input)
    if not input or input == '' then
      return
    end

    -- スレッドに返信
    get_api().reply_message(thread_info.ts, input, function(success)
      if success then
        notify('スレッドに返信しました', vim.log.levels.INFO)
        -- スレッドを更新
        M.refresh_thread()
      else
        notify('スレッド返信に失敗しました', vim.log.levels.ERROR)
      end
    end)
  end)
end

-- スレッドにリアクションを追加
function M.add_reaction_to_thread()
  local layout = get_layout()
  if not layout.layout.thread_buf or not vim.api.nvim_buf_is_valid(layout.layout.thread_buf) then
    return
  end

  -- カーソル位置の行を取得
  local cursor = vim.api.nvim_win_get_cursor(layout.layout.thread_win)
  local line = cursor[1] - 1 -- 0-indexedに変換

  -- メッセージを取得
  local message = layout.layout.line_to_thread_message and layout.layout.line_to_thread_message[line]
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
        -- スレッドを更新
        M.refresh_thread()
      else
        notify('リアクションの追加に失敗しました', vim.log.levels.ERROR)
      end
    end)
  end)
end

-- スレッド表示を閉じる
function M.close_thread()
  local layout = get_layout()

  -- スレッドウィンドウを閉じる
  if layout.layout.thread_win and vim.api.nvim_win_is_valid(layout.layout.thread_win) then
    vim.api.nvim_win_close(layout.layout.thread_win, true)
    layout.layout.thread_win = nil
  end

  -- スレッドバッファを削除
  if layout.layout.thread_buf and vim.api.nvim_buf_is_valid(layout.layout.thread_buf) then
    vim.api.nvim_buf_delete(layout.layout.thread_buf, { force = true })
    layout.layout.thread_buf = nil
  end

  -- スレッド情報をクリア
  get_state().set_current_thread(nil, nil)
  layout.layout.line_to_thread_message = nil

  -- メッセージウィンドウにフォーカス
  if layout.layout.messages_win and vim.api.nvim_win_is_valid(layout.layout.messages_win) then
    vim.api.nvim_set_current_win(layout.layout.messages_win)
  end
end

return M