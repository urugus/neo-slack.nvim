---@brief [[
--- neo-slack.nvim UI モジュール
--- ユーザーインターフェースを構築します
---@brief ]]

local api = require('neo-slack.api.init')
local utils = require('neo-slack.utils')
local state = require('neo-slack.state')
local events = require('neo-slack.core.events')
local config = require('neo-slack.core.config')

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
  utils.notify(message, level, opts)
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
  -- 既存のウィンドウを閉じる
  M.close()
  
  -- レイアウトを計算
  local layout = calculate_layout()
  if not layout then
    return
  end
  
  -- バッファを作成
  M.layout.channels_buf = create_buffer('Neo-Slack-Channels', 'neo-slack-channels', false)
  M.layout.messages_buf = create_buffer('Neo-Slack-Messages', 'neo-slack-messages', false)
  
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
  
  -- チャンネル一覧を表示
  api.get_channels(function(success, channels)
    if success then
      M.show_channels(channels)
    else
      notify('チャンネル一覧の取得に失敗しました', vim.log.levels.ERROR)
    end
  end)
  
  -- キーマッピングを設定
  M.setup_keymaps()
  
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
    local opts = { noremap = true, silent = true, buffer = M.layout.channels_buf }
    
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
    local opts = { noremap = true, silent = true, buffer = M.layout.messages_buf }
    
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
    local opts = { noremap = true, silent = true, buffer = M.layout.thread_buf }
    
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
  if not M.layout.channels_buf or not vim.api.nvim_buf_is_valid(M.layout.channels_buf) then
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
  for id, _ in pairs(state.starred_channels) do
    starred_ids[id] = true
  end
  
  -- カスタムセクションの初期化
  for id, section in pairs(state.custom_sections) do
    custom_sections[id] = {
      name = section.name,
      channels = {},
      is_collapsed = state.is_section_collapsed(id)
    }
  end
  
  -- チャンネルを分類
  for _, channel in ipairs(channels) do
    -- スター付きチャンネル
    if starred_ids[channel.id] then
      table.insert(starred_channels, channel)
    end
    
    -- カスタムセクションに属するチャンネル
    local section_id = state.get_channel_section(channel.id)
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
    api.get_user_info_by_id(dm.user, function(success, user_data)
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
  local starred_collapsed = state.is_section_collapsed('starred')
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
  local channels_collapsed = state.is_section_collapsed('channels')
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
    local private_collapsed = state.is_section_collapsed('private')
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
    local dm_collapsed = state.is_section_collapsed('dm')
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
    local group_collapsed = state.is_section_collapsed('group')
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
  local current_channel_id = state.get_current_channel()
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
  for _, channel in ipairs(state.get_channels()) do
    if channel.id == channel_id then
      channel_name = channel.name
      break
    end
  end
  
  -- チャンネル選択イベントを発行
  events.emit('channel_selected', channel_id, channel_name)
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
  local is_collapsed = state.is_section_collapsed(section_info.id)
  state.set_section_collapsed(section_info.id, not is_collapsed)
  
  -- 状態を保存
  state.save_section_collapsed()
  
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
  local is_starred = state.is_channel_starred(channel_id)
  state.set_channel_starred(channel_id, not is_starred)
  
  -- 状態を保存
  state.save_starred_channels()
  
  -- チャンネル一覧を再表示
  M.refresh_channels()
end

-- チャンネル一覧を更新
function M.refresh_channels()
  api.get_channels(function(success, channels)
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
  if not M.layout.messages_buf or not vim.api.nvim_buf_is_valid(M.layout.messages_buf) then
    return
  end
  
  -- チャンネル情報を取得
  local channel_id = channel
  local channel_name = channel
  
  -- チャンネルオブジェクトを検索
  for _, ch in ipairs(state.get_channels()) do
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
  if not messages or #messages == 0 then
    vim.api.nvim_buf_set_option(M.layout.messages_buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(M.layout.messages_buf, 0, -1, false, {'メッセージがありません'})
    vim.api.nvim_buf_set_option(M.layout.messages_buf, 'modifiable', false)
    return
  end
  
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
    -- ユーザー情報を取得
    local user_id = message.user
