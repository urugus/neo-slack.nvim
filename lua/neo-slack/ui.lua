---@brief [[
--- neo-slack.nvim UI モジュール
--- ユーザーインターフェースを構築します
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_api() return dependency.get('api') end
local function get_utils() return dependency.get('utils') end
local function get_state() return dependency.get('state') end
local function get_events() return dependency.get('core.events') end
local function get_config() return dependency.get('core.config') end

---@class NeoSlackUI
---@field layout table レイアウト情報
local M = {}

-- レイアウト情報
M.layout = {
  channels_win = nil,
  messages_win = nil,
  thread_win = nil,
  channels_buf = nil,
  messages_buf = nil,
  thread_buf = nil,
  channels_width = 30,
  messages_width = 70,
  thread_width = 50,
  min_width = 120,
  min_height = 30,
}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
local function notify(message, level, opts)
  opts = opts or {}
  opts.prefix = 'UI: '
  get_utils().notify(message, level, opts)
end

-- バッファを作成
---@param name string バッファ名
---@param filetype string|nil ファイルタイプ
---@param modifiable boolean|nil 編集可能かどうか
---@return number バッファID
local function create_buffer(name, filetype, modifiable)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)

  if filetype then
    vim.api.nvim_buf_set_option(buf, 'filetype', filetype)
  end

  vim.api.nvim_buf_set_option(buf, 'modifiable', modifiable or false)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'hide')
  vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)

  return buf
end

-- ウィンドウを作成
---@param buf number バッファID
---@param width number 幅
---@param height number 高さ
---@param row number 行位置
---@param col number 列位置
---@param border string|nil ボーダータイプ
---@param title string|nil タイトル
---@return number ウィンドウID
local function create_window(buf, width, height, row, col, border, title)
  local win_opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = border or 'single',
    title = title,
  }

  local win = vim.api.nvim_open_win(buf, false, win_opts)
  vim.api.nvim_win_set_option(win, 'wrap', true)
  vim.api.nvim_win_set_option(win, 'cursorline', true)
  vim.api.nvim_win_set_option(win, 'winhl', 'Normal:NeoSlackNormal,FloatBorder:NeoSlackBorder')

  return win
end

-- レイアウトを計算
---@return table レイアウト情報
local function calculate_layout()
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines - vim.o.cmdheight - 1

  -- 最小サイズをチェック
  if editor_width < M.layout.min_width or editor_height < M.layout.min_height then
    notify('エディタのサイズが小さすぎます。最小サイズ: ' .. M.layout.min_width .. 'x' .. M.layout.min_height, vim.log.levels.WARN)
    return nil
  end

  -- 各ウィンドウの幅と高さを計算
  local channels_width = M.layout.channels_width
  local messages_width = editor_width - channels_width - 4 -- ボーダーの分を引く
  local height = editor_height - 4 -- ボーダーの分を引く

  -- レイアウト情報を返す
  return {
    editor_width = editor_width,
    editor_height = editor_height,
    channels_width = channels_width,
    messages_width = messages_width,
    height = height,
  }
end

-- UIを表示
function M.show()
  notify('UI表示を開始します', vim.log.levels.INFO)

  -- 既存のウィンドウを閉じる
  M.close()

  -- レイアウトを計算
  local layout = calculate_layout()
  if not layout then
    notify('レイアウトの計算に失敗しました', vim.log.levels.ERROR)
    return
  end

  notify('バッファを作成します', vim.log.levels.INFO)
  -- バッファを作成
  M.layout.channels_buf = create_buffer('Neo-Slack-Channels', 'neo-slack-channels', false)
  M.layout.messages_buf = create_buffer('Neo-Slack-Messages', 'neo-slack-messages', false)

  notify('ウィンドウを作成します', vim.log.levels.INFO)
  -- ウィンドウを作成
  M.layout.channels_win = create_window(
    M.layout.channels_buf,
    layout.channels_width,
    layout.height,
    2,
    2,
    'single',
    'Channels'
  )

  M.layout.messages_win = create_window(
    M.layout.messages_buf,
    layout.messages_width,
    layout.height,
    2,
    layout.channels_width + 3,
    'single',
    'Messages'
  )

  notify('チャンネル一覧を取得します', vim.log.levels.INFO)
  -- チャンネル一覧を表示
  get_api().get_channels(function(success, channels)
    if success then
      notify('UIからチャンネル一覧の取得に成功しました: ' .. #channels .. '件', vim.log.levels.INFO)
      M.show_channels(channels)
    else
      notify('UIからチャンネル一覧の取得に失敗しました', vim.log.levels.ERROR)
    end
  end)

  notify('キーマッピングを設定します', vim.log.levels.INFO)
  -- キーマッピングを設定
  M.setup_keymaps()

  notify('最初のウィンドウにフォーカスします', vim.log.levels.INFO)
  -- 最初のウィンドウにフォーカス
  vim.api.nvim_set_current_win(M.layout.channels_win)
end

-- UIを閉じる
function M.close()
  -- ウィンドウを閉じる
  for _, win_name in ipairs({'channels_win', 'messages_win', 'thread_win'}) do
    local win = M.layout[win_name]
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
      M.layout[win_name] = nil
    end
  end

  -- バッファを削除
  for _, buf_name in ipairs({'channels_buf', 'messages_buf', 'thread_buf'}) do
    local buf = M.layout[buf_name]
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
      M.layout[buf_name] = nil
    end
  end
end

-- キーマッピングを設定
function M.setup_keymaps()
  -- チャンネル一覧のキーマッピング
  if M.layout.channels_buf and vim.api.nvim_buf_is_valid(M.layout.channels_buf) then
    local opts = { noremap = true, silent = true }

    -- Enter: チャンネルを選択
    vim.api.nvim_buf_set_keymap(M.layout.channels_buf, 'n', '<CR>', [[<cmd>lua require('neo-slack.ui').select_channel()<CR>]], opts)

    -- r: チャンネル一覧を更新
    vim.api.nvim_buf_set_keymap(M.layout.channels_buf, 'n', 'r', [[<cmd>lua require('neo-slack.ui').refresh_channels()<CR>]], opts)

    -- q: UIを閉じる
    vim.api.nvim_buf_set_keymap(M.layout.channels_buf, 'n', 'q', [[<cmd>lua require('neo-slack.ui').close()<CR>]], opts)

    -- s: チャンネルをスター付き/解除
    vim.api.nvim_buf_set_keymap(M.layout.channels_buf, 'n', 's', [[<cmd>lua require('neo-slack.ui').toggle_star_channel()<CR>]], opts)

    -- c: セクションの折りたたみ/展開
    vim.api.nvim_buf_set_keymap(M.layout.channels_buf, 'n', 'c', [[<cmd>lua require('neo-slack.ui').toggle_section()<CR>]], opts)
  end

  -- メッセージ一覧のキーマッピング
  if M.layout.messages_buf and vim.api.nvim_buf_is_valid(M.layout.messages_buf) then
    local opts = { noremap = true, silent = true }

    -- Enter: スレッドを表示
    vim.api.nvim_buf_set_keymap(M.layout.messages_buf, 'n', '<CR>', [[<cmd>lua require('neo-slack.ui').show_thread()<CR>]], opts)

    -- r: メッセージ一覧を更新
    vim.api.nvim_buf_set_keymap(M.layout.messages_buf, 'n', 'r', [[<cmd>lua require('neo-slack.ui').refresh_messages()<CR>]], opts)

    -- m: 新しいメッセージを送信
    vim.api.nvim_buf_set_keymap(M.layout.messages_buf, 'n', 'm', [[<cmd>lua require('neo-slack.ui').send_message()<CR>]], opts)

    -- a: リアクションを追加
    vim.api.nvim_buf_set_keymap(M.layout.messages_buf, 'n', 'a', [[<cmd>lua require('neo-slack.ui').add_reaction()<CR>]], opts)

    -- q: UIを閉じる
    vim.api.nvim_buf_set_keymap(M.layout.messages_buf, 'n', 'q', [[<cmd>lua require('neo-slack.ui').close()<CR>]], opts)
  end

  -- スレッド表示のキーマッピング
  if M.layout.thread_buf and vim.api.nvim_buf_is_valid(M.layout.thread_buf) then
    local opts = { noremap = true, silent = true }

    -- r: スレッドを更新
    vim.api.nvim_buf_set_keymap(M.layout.thread_buf, 'n', 'r', [[<cmd>lua require('neo-slack.ui').refresh_thread()<CR>]], opts)

    -- m: スレッドに返信
    vim.api.nvim_buf_set_keymap(M.layout.thread_buf, 'n', 'm', [[<cmd>lua require('neo-slack.ui').reply_to_thread()<CR>]], opts)

    -- a: リアクションを追加
    vim.api.nvim_buf_set_keymap(M.layout.thread_buf, 'n', 'a', [[<cmd>lua require('neo-slack.ui').add_reaction_to_thread()<CR>]], opts)

    -- q: スレッド表示を閉じる
    vim.api.nvim_buf_set_keymap(M.layout.thread_buf, 'n', 'q', [[<cmd>lua require('neo-slack.ui').close_thread()<CR>]], opts)
  end
end

-- チャンネル一覧を表示
---@param channels table[] チャンネルオブジェクトの配列
function M.show_channels(channels)
  notify('UIにチャンネル一覧を表示します: ' .. (channels and #channels or 0) .. '件', vim.log.levels.INFO)

  if not M.layout.channels_buf or not vim.api.nvim_buf_is_valid(M.layout.channels_buf) then
    notify('チャンネルバッファが無効です', vim.log.levels.ERROR)
    return
  end

  -- チャンネルを種類ごとに分類
  local public_channels = {}
  local private_channels = {}
  local direct_messages = {}
  local group_messages = {}
  local starred_channels = {}
  local custom_sections = {}

  -- スター付きチャンネルのIDを取得
  local starred_ids = {}
  for id, _ in pairs(get_state().starred_channels) do
    starred_ids[id] = true
  end

  -- カスタムセクションの初期化
  for id, section in pairs(get_state().custom_sections) do
    custom_sections[id] = {
      name = section.name,
      channels = {},
      is_collapsed = get_state().is_section_collapsed(id)
    }
  end

  -- チャンネルを分類
  for _, channel in ipairs(channels) do
    -- スター付きチャンネル
    if starred_ids[channel.id] then
      table.insert(starred_channels, channel)
    end

    -- カスタムセクションに属するチャンネル
    local section_id = get_state().get_channel_section(channel.id)
    if section_id and custom_sections[section_id] then
      table.insert(custom_sections[section_id].channels, channel)
      goto continue
    end

    -- 通常の分類
    if channel.is_channel then
      -- パブリックチャンネル
      table.insert(public_channels, channel)
    elseif channel.is_group or channel.is_private then
      -- プライベートチャンネル
      table.insert(private_channels, channel)
    elseif channel.is_im then
      -- ダイレクトメッセージ
      table.insert(direct_messages, channel)
    elseif channel.is_mpim then
      -- グループメッセージ
      table.insert(group_messages, channel)
    end

    ::continue::
  end

  -- チャンネル名でソート
  local function sort_by_name(a, b)
    local name_a = a.name or ''
    local name_b = b.name or ''
    return name_a < name_b
  end

  table.sort(public_channels, sort_by_name)
  table.sort(private_channels, sort_by_name)
  table.sort(starred_channels, sort_by_name)

  -- DMとグループメッセージは特別な処理が必要
  for _, dm in ipairs(direct_messages) do
    -- ユーザー名を取得
    get_api().get_user_info_by_id(dm.user, function(success, user_data)
      if success and user_data then
        -- DMの名前をユーザー名に設定
        local display_name = user_data.profile.display_name
        local real_name = user_data.profile.real_name
        dm.name = (display_name and display_name ~= '') and display_name or real_name
      else
        dm.name = 'unknown-user'
      end
    end)
  end

  -- バッファを編集可能に設定
  vim.api.nvim_buf_set_option(M.layout.channels_buf, 'modifiable', true)

  -- バッファをクリア
  vim.api.nvim_buf_set_lines(M.layout.channels_buf, 0, -1, false, {})

  -- 行とチャンネルIDのマッピング
  local line_to_channel = {}
  local line_to_section = {}
  local current_line = 0

  -- スター付きセクション
  local starred_collapsed = get_state().is_section_collapsed('starred')
  table.insert(line_to_section, { line = current_line, id = 'starred', name = 'スター付き' })
  vim.api.nvim_buf_set_lines(M.layout.channels_buf, current_line, current_line + 1, false, {'▼ スター付き'})
  current_line = current_line + 1

  if not starred_collapsed and #starred_channels > 0 then
    for _, channel in ipairs(starred_channels) do
      local prefix = channel.is_channel and '#' or (channel.is_private or channel.is_group) and '🔒' or (channel.is_im) and '@' or '👥'
      local name = channel.name or 'unknown'
      vim.api.nvim_buf_set_lines(M.layout.channels_buf, current_line, current_line + 1, false, {'  ' .. prefix .. ' ' .. name})
      line_to_channel[current_line] = channel.id
      current_line = current_line + 1
    end
  end

  -- カスタムセクション
  for id, section in pairs(custom_sections) do
    if #section.channels > 0 then
      local collapsed_mark = section.is_collapsed and '▶' or '▼'
      table.insert(line_to_section, { line = current_line, id = id, name = section.name })
      vim.api.nvim_buf_set_lines(M.layout.channels_buf, current_line, current_line + 1, false, {collapsed_mark .. ' ' .. section.name})
      current_line = current_line + 1

      if not section.is_collapsed then
        for _, channel in ipairs(section.channels) do
          local prefix = channel.is_channel and '#' or (channel.is_private or channel.is_group) and '🔒' or (channel.is_im) and '@' or '👥'
          local name = channel.name or 'unknown'
          vim.api.nvim_buf_set_lines(M.layout.channels_buf, current_line, current_line + 1, false, {'  ' .. prefix .. ' ' .. name})
          line_to_channel[current_line] = channel.id
          current_line = current_line + 1
        end
      end
    end
  end

  -- チャンネルセクション
  local channels_collapsed = get_state().is_section_collapsed('channels')
  table.insert(line_to_section, { line = current_line, id = 'channels', name = 'チャンネル' })
  vim.api.nvim_buf_set_lines(M.layout.channels_buf, current_line, current_line + 1, false, {(channels_collapsed and '▶' or '▼') .. ' チャンネル'})
  current_line = current_line + 1

  if not channels_collapsed then
    for _, channel in ipairs(public_channels) do
      vim.api.nvim_buf_set_lines(M.layout.channels_buf, current_line, current_line + 1, false, {'  # ' .. channel.name})
      line_to_channel[current_line] = channel.id
      current_line = current_line + 1
    end
  end

  -- プライベートチャンネルセクション
  if #private_channels > 0 then
    local private_collapsed = get_state().is_section_collapsed('private')
    table.insert(line_to_section, { line = current_line, id = 'private', name = 'プライベートチャンネル' })
    vim.api.nvim_buf_set_lines(M.layout.channels_buf, current_line, current_line + 1, false, {(private_collapsed and '▶' or '▼') .. ' プライベートチャンネル'})
    current_line = current_line + 1

    if not private_collapsed then
      for _, channel in ipairs(private_channels) do
        vim.api.nvim_buf_set_lines(M.layout.channels_buf, current_line, current_line + 1, false, {'  🔒 ' .. channel.name})
        line_to_channel[current_line] = channel.id
        current_line = current_line + 1
      end
    end
  end

  -- DMセクション
  if #direct_messages > 0 then
    local dm_collapsed = get_state().is_section_collapsed('dm')
    table.insert(line_to_section, { line = current_line, id = 'dm', name = 'ダイレクトメッセージ' })
    vim.api.nvim_buf_set_lines(M.layout.channels_buf, current_line, current_line + 1, false, {(dm_collapsed and '▶' or '▼') .. ' ダイレクトメッセージ'})
    current_line = current_line + 1

    if not dm_collapsed then
      for _, channel in ipairs(direct_messages) do
        local name = channel.name or 'unknown-user'
        vim.api.nvim_buf_set_lines(M.layout.channels_buf, current_line, current_line + 1, false, {'  @ ' .. name})
        line_to_channel[current_line] = channel.id
        current_line = current_line + 1
      end
    end
  end

  -- グループメッセージセクション
  if #group_messages > 0 then
    local group_collapsed = get_state().is_section_collapsed('group')
    table.insert(line_to_section, { line = current_line, id = 'group', name = 'グループメッセージ' })
    vim.api.nvim_buf_set_lines(M.layout.channels_buf, current_line, current_line + 1, false, {(group_collapsed and '▶' or '▼') .. ' グループメッセージ'})
    current_line = current_line + 1

    if not group_collapsed then
      for _, channel in ipairs(group_messages) do
        local name = channel.name or 'unknown-group'
        vim.api.nvim_buf_set_lines(M.layout.channels_buf, current_line, current_line + 1, false, {'  👥 ' .. name})
        line_to_channel[current_line] = channel.id
        current_line = current_line + 1
      end
    end
  end

  -- バッファを編集不可に設定
  vim.api.nvim_buf_set_option(M.layout.channels_buf, 'modifiable', false)

  -- 行とチャンネルIDのマッピングを保存
  M.layout.line_to_channel = line_to_channel
  M.layout.line_to_section = line_to_section

  -- 現在のチャンネルをハイライト
  M.highlight_current_channel()
end

-- 現在のチャンネルをハイライト
function M.highlight_current_channel()
  if not M.layout.channels_buf or not vim.api.nvim_buf_is_valid(M.layout.channels_buf) then
    return
  end

  -- 既存のハイライトをクリア
  vim.api.nvim_buf_clear_namespace(M.layout.channels_buf, -1, 0, -1)

  -- 現在のチャンネルIDを取得
  local current_channel_id = get_state().get_current_channel()
  if not current_channel_id then
    return
  end

  -- チャンネルIDに対応する行を検索
  for line, channel_id in pairs(M.layout.line_to_channel or {}) do
    if channel_id == current_channel_id then
      -- 行をハイライト
      vim.api.nvim_buf_add_highlight(M.layout.channels_buf, -1, 'NeoSlackCurrentChannel', line, 0, -1)
      break
    end
  end
end

-- チャンネルを選択
function M.select_channel()
  if not M.layout.channels_buf or not vim.api.nvim_buf_is_valid(M.layout.channels_buf) then
    return
  end

  -- カーソル位置の行を取得
  local cursor = vim.api.nvim_win_get_cursor(M.layout.channels_win)
  local line = cursor[1] - 1 -- 0-indexedに変換

  -- セクションヘッダーの場合は折りたたみ/展開
  for _, section in ipairs(M.layout.line_to_section or {}) do
    if section.line == line then
      M.toggle_section()
      return
    end
  end

  -- チャンネルIDを取得
  local channel_id = M.layout.line_to_channel and M.layout.line_to_channel[line]
  if not channel_id then
    return
  end

  -- チャンネル名を取得
  local channel_name
  for _, channel in ipairs(get_state().get_channels()) do
    if channel.id == channel_id then
      channel_name = channel.name
      break
    end
  end

  -- チャンネル選択イベントを発行
  get_events().emit('channel_selected', channel_id, channel_name)
end

-- セクションの折りたたみ/展開を切り替え
function M.toggle_section()
  if not M.layout.channels_buf or not vim.api.nvim_buf_is_valid(M.layout.channels_buf) then
    return
  end

  -- カーソル位置の行を取得
  local cursor = vim.api.nvim_win_get_cursor(M.layout.channels_win)
  local line = cursor[1] - 1 -- 0-indexedに変換

  -- セクション情報を取得
  local section_info
  for _, section in ipairs(M.layout.line_to_section or {}) do
    if section.line == line then
      section_info = section
      break
    end
  end

  if not section_info then
    return
  end

  -- 折りたたみ状態を切り替え
  local state_module = get_state()
  local is_collapsed = state_module.is_section_collapsed(section_info.id)
  state_module.set_section_collapsed(section_info.id, not is_collapsed)

  -- 状態を保存
  state_module.save_section_collapsed()

  -- チャンネル一覧を再表示
  M.refresh_channels()
end

-- チャンネルのスター付き/解除を切り替え
function M.toggle_star_channel()
  if not M.layout.channels_buf or not vim.api.nvim_buf_is_valid(M.layout.channels_buf) then
    return
  end

  -- カーソル位置の行を取得
  local cursor = vim.api.nvim_win_get_cursor(M.layout.channels_win)
  local line = cursor[1] - 1 -- 0-indexedに変換

  -- チャンネルIDを取得
  local channel_id = M.layout.line_to_channel and M.layout.line_to_channel[line]
  if not channel_id then
    return
  end

  -- スター付き状態を切り替え
  local state_module = get_state()
  local is_starred = state_module.is_channel_starred(channel_id)
  state_module.set_channel_starred(channel_id, not is_starred)

  -- 状態を保存
  state_module.save_starred_channels()

  -- チャンネル一覧を再表示
  M.refresh_channels()
end

-- チャンネル一覧を更新
function M.refresh_channels()
  get_api().get_channels(function(success, channels)
    if success then
      M.show_channels(channels)
    else
      notify('チャンネル一覧の更新に失敗しました', vim.log.levels.ERROR)
    end
  end)
end

-- メッセージ一覧を表示
---@param channel string|nil チャンネル名またはID
---@param messages table[]|nil メッセージオブジェクトの配列
function M.show_messages(channel, messages)
  notify('show_messages関数が呼び出されました: channel=' .. tostring(channel) .. ', messages=' .. tostring(messages and #messages or 0) .. '件', vim.log.levels.INFO)

  -- messagesの型を確認
  notify('messagesの型: ' .. type(messages), vim.log.levels.INFO)

  -- messagesが配列の場合、その内容を確認
  if type(messages) == 'table' then
    notify('messagesの内容: ' .. vim.inspect(messages):sub(1, 100) .. '...', vim.log.levels.INFO)

    -- messagesの各要素の型を確認
    for i, msg in ipairs(messages) do
      notify('messages[' .. i .. ']の型: ' .. type(msg), vim.log.levels.INFO)
      if i >= 3 then break end -- 最初の3つだけ確認
    end

    -- #messagesの値を確認
    notify('#messagesの値: ' .. #messages, vim.log.levels.INFO)
  end

  if not M.layout.messages_buf or not vim.api.nvim_buf_is_valid(M.layout.messages_buf) then
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
  if M.layout.messages_win and vim.api.nvim_win_is_valid(M.layout.messages_win) then
    vim.api.nvim_win_set_config(M.layout.messages_win, {
      title = 'Messages: ' .. channel_name
    })
  end

  -- メッセージがない場合
  if not messages then
    notify('messagesがnilです', vim.log.levels.ERROR)
    vim.api.nvim_buf_set_option(M.layout.messages_buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(M.layout.messages_buf, 0, -1, false, {'メッセージがありません (nil)'})
    vim.api.nvim_buf_set_option(M.layout.messages_buf, 'modifiable', false)
    return
  end

  if #messages == 0 then
    notify('messagesが空の配列です', vim.log.levels.INFO)
    vim.api.nvim_buf_set_option(M.layout.messages_buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(M.layout.messages_buf, 0, -1, false, {'メッセージがありません (空の配列)'})
    vim.api.nvim_buf_set_option(M.layout.messages_buf, 'modifiable', false)
    return
  end

  notify('メッセージを表示します: ' .. #messages .. '件', vim.log.levels.INFO)

  -- メッセージを時系列順にソート
  table.sort(messages, function(a, b)
    return tonumber(a.ts) < tonumber(b.ts)
  end)

  -- バッファを編集可能に設定
  vim.api.nvim_buf_set_option(M.layout.messages_buf, 'modifiable', true)

  -- バッファをクリア
  vim.api.nvim_buf_set_lines(M.layout.messages_buf, 0, -1, false, {})

  -- 行とメッセージのマッピング
  local line_to_message = {}
  local current_line = 0

  -- メッセージを表示
  for _, message in ipairs(messages) do
    -- デバッグ情報を追加
    notify('メッセージ情報: ' .. vim.inspect(message), vim.log.levels.DEBUG)

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

      -- ユーザー情報が取得できなかった場合のみ非同期で取得を試みる
      if not user_data and user_id then
        get_api().get_user_info_by_id(user_id, function(success, user_data)
          if success and user_data then
            -- ユーザー情報をキャッシュに保存
            get_state().set_user_cache(user_id, user_data)
          end
        end)
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
    vim.api.nvim_buf_set_lines(M.layout.messages_buf, current_line, current_line + 1, false, {header})
    line_to_message[current_line] = message
    current_line = current_line + 1

    -- メッセージ内容を表示
    local text = message.text or "(内容なし)"

    -- リッチテキスト形式のメッセージの場合、特殊な処理を行う
    if message.blocks then
      -- デバッグ情報を追加
      notify('メッセージにblocksフィールドがあります: ' .. vim.inspect(message.blocks), vim.log.levels.DEBUG)

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
        notify('リッチテキストを抽出しました: ' .. text:sub(1, 100) .. '...', vim.log.levels.DEBUG)
      end
    end

    local lines = get_utils().split_lines(text)

    -- メッセージ行を追加
    for _, line in ipairs(lines) do
      vim.api.nvim_buf_set_lines(M.layout.messages_buf, current_line, current_line + 1, false, {"  " .. line})
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
      vim.api.nvim_buf_set_lines(M.layout.messages_buf, current_line, current_line + 1, false, {reactions_text})
      line_to_message[current_line] = message
      current_line = current_line + 1
    end

    -- スレッドがある場合は表示
    if message.thread_ts and message.reply_count and message.reply_count > 0 then
      local thread_text = "  スレッド: " .. message.reply_count .. "件の返信"
      vim.api.nvim_buf_set_lines(M.layout.messages_buf, current_line, current_line + 1, false, {thread_text})
      line_to_message[current_line] = message
      current_line = current_line + 1
    end

    -- 空行を追加
    vim.api.nvim_buf_set_lines(M.layout.messages_buf, current_line, current_line + 1, false, {""})
    current_line = current_line + 1
  end

  -- バッファを編集不可に設定
  vim.api.nvim_buf_set_option(M.layout.messages_buf, 'modifiable', false)

  -- 行とメッセージのマッピングを保存
  M.layout.line_to_message = line_to_message

  -- メッセージ表示完了の通知
  notify('メッセージ表示が完了しました: ' .. current_line .. '行', vim.log.levels.INFO)

  -- メッセージウィンドウにフォーカス
  if M.layout.messages_win and vim.api.nvim_win_is_valid(M.layout.messages_win) then
    vim.api.nvim_set_current_win(M.layout.messages_win)
  end
end

return M
