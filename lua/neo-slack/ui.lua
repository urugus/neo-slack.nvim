---@brief [[
--- neo-slack.nvim UI モジュール
--- ユーザーインターフェースを構築します
---@brief ]]

local api = require('neo-slack.api')
local utils = require('neo-slack.utils')
local state = require('neo-slack.state')

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
}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
local function notify(message, level)
  vim.notify('Neo-Slack: ' .. message, level)
end

-- バッファオプションを設定
---@param bufnr number バッファ番号
---@param filetype string ファイルタイプ
local function setup_buffer_options(bufnr, filetype)
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(bufnr, 'bufhidden', 'hide')
  vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', filetype)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
end

-- 分割レイアウトを設定
---@return nil
function M.setup_split_layout()
  -- 既存のスレッドウィンドウを閉じる
  if M.layout.thread_win and vim.api.nvim_win_is_valid(M.layout.thread_win) then
    vim.api.nvim_win_close(M.layout.thread_win, true)
    M.layout.thread_win = nil
    M.layout.thread_buf = nil
  end
  
  -- チャンネル一覧用のウィンドウが存在しない場合は作成
  if not M.layout.channels_win or not vim.api.nvim_win_is_valid(M.layout.channels_win) then
    -- 現在のウィンドウを全画面に
    vim.cmd('only')
    
    -- 現在のウィンドウをメッセージ用に設定
    M.layout.messages_win = vim.api.nvim_get_current_win()
    
    -- 左側に新しいウィンドウを作成（チャンネル一覧用）
    vim.cmd('leftabove vsplit')
    M.layout.channels_win = vim.api.nvim_get_current_win()
    
    -- チャンネル一覧の幅を設定
    vim.api.nvim_win_set_width(M.layout.channels_win, 30)
    
    -- メッセージウィンドウに戻る
    vim.cmd('wincmd l')
  end
end

-- スレッド表示用のレイアウトを設定
---@return nil
function M.setup_thread_layout()
  -- 分割レイアウトを設定
  M.setup_split_layout()
  
  -- スレッド用のウィンドウが存在しない場合は作成
  if not M.layout.thread_win or not vim.api.nvim_win_is_valid(M.layout.thread_win) then
    -- メッセージウィンドウにフォーカス
    vim.api.nvim_set_current_win(M.layout.messages_win)
    
    -- 右側に新しいウィンドウを作成（スレッド用）
    vim.cmd('rightbelow vsplit')
    M.layout.thread_win = vim.api.nvim_get_current_win()
    
    -- スレッドウィンドウとメッセージウィンドウの幅を調整
    local total_width = vim.o.columns
    local channels_width = 30
    local remaining_width = total_width - channels_width
    local thread_width = math.floor(remaining_width / 2)
    
    vim.api.nvim_win_set_width(M.layout.thread_win, thread_width)
    
    -- メッセージウィンドウに戻って幅を調整
    vim.cmd('wincmd h')
    vim.api.nvim_win_set_width(M.layout.messages_win, thread_width)
    
    -- スレッドウィンドウに戻る
    vim.cmd('wincmd l')
  end
end

-- バッファを作成または取得
---@param name string バッファ名
---@return number バッファ番号
function M.get_or_create_buffer(name)
  local bufname = 'neo-slack://' .. name
  
  -- 既存のバッファを探す
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == bufname then
      return buf
    end
  end
  
  -- 新しいバッファを作成
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, bufname)
  
  return bufnr
end

-- セクションの折りたたみ/展開を切り替える
---@param section_name string セクション名またはID
---@return nil
function M.toggle_section_collapse(section_name)
  local is_collapsed = state.is_section_collapsed(section_name)
  state.set_section_collapsed(section_name, not is_collapsed)
  
  -- 折りたたみ状態を保存
  state.save_section_collapsed()
  
  -- チャンネル一覧を更新
  -- 循環参照を避けるため、package.loadedを使用
  local neo_slack = package.loaded['neo-slack']
  if neo_slack then
    neo_slack.list_channels()
  end
  
  -- セクション名を取得（IDの場合はセクション名に変換）
  local display_name = section_name
  if state.custom_sections[section_name] then
    display_name = state.custom_sections[section_name].name
  end
  
  -- 通知
  if not is_collapsed then
    notify(display_name .. ' セクションを折りたたみました', vim.log.levels.INFO)
  else
    notify(display_name .. ' セクションを展開しました', vim.log.levels.INFO)
  end
end

-- セクション作成ダイアログを表示
function M.create_section_dialog()
  vim.ui.input({ prompt = 'セクション名: ' }, function(input)
    if input and input ~= '' then
      local section_id = state.add_section(input)
      -- セクション情報を保存
      state.save_custom_sections()
      -- チャンネル一覧を更新
      local neo_slack = package.loaded['neo-slack']
      if neo_slack then
        neo_slack.list_channels()
      end
      notify('セクション「' .. input .. '」を作成しました', vim.log.levels.INFO)
    end
  end)
end

-- セクション編集ダイアログを表示
---@param section_id string セクションID
function M.edit_section_dialog(section_id)
  local section = state.custom_sections[section_id]
  if not section then return end
  
  vim.ui.input({
    prompt = 'セクション名: ',
    default = section.name
  }, function(input)
    if input and input ~= '' then
      section.name = input
      -- セクション情報を保存
      state.save_custom_sections()
      -- チャンネル一覧を更新
      local neo_slack = package.loaded['neo-slack']
      if neo_slack then
        neo_slack.list_channels()
      end
      notify('セクション名を「' .. input .. '」に変更しました', vim.log.levels.INFO)
    end
  end)
end

-- セクション削除確認ダイアログを表示
---@param section_id string セクションID
function M.delete_section_dialog(section_id)
  local section = state.custom_sections[section_id]
  if not section then return end
  
  vim.ui.input({
    prompt = 'セクション「' .. section.name .. '」を削除しますか？ (y/N): '
  }, function(input)
    if input and (input:lower() == 'y' or input:lower() == 'yes') then
      state.remove_section(section_id)
      -- セクション情報を保存
      state.save_custom_sections()
      state.save_channel_section_map()
      -- チャンネル一覧を更新
      local neo_slack = package.loaded['neo-slack']
      if neo_slack then
        neo_slack.list_channels()
      end
      notify('セクション「' .. section.name .. '」を削除しました', vim.log.levels.INFO)
    end
  end)
end

-- チャンネルをセクションに割り当てるダイアログを表示
---@param channel_id string チャンネルID
function M.assign_channel_dialog(channel_id)
  local channel = state.get_channel_by_id(channel_id)
  if not channel then return end
  
  -- セクション一覧を作成
  local sections = {}
  table.insert(sections, { id = nil, name = '(なし)' })
  for id, section in pairs(state.custom_sections) do
    table.insert(sections, { id = id, name = section.name })
  end
  
  -- セクション選択肢を作成
  local choices = {}
  for i, section in ipairs(sections) do
    table.insert(choices, i .. '. ' .. section.name)
  end
  
  -- 現在のセクションを取得
  local current_section_id = state.get_channel_section(channel_id)
  local current_index = 1
  for i, section in ipairs(sections) do
    if section.id == current_section_id then
      current_index = i
      break
    end
  end
  
  vim.ui.select(choices, {
    prompt = 'チャンネル「' .. channel.name .. '」のセクションを選択:',
    default = current_index
  }, function(choice, idx)
    if choice and idx then
      local section = sections[idx]
      state.assign_channel_to_section(channel_id, section.id)
      -- セクション情報を保存
      state.save_channel_section_map()
      -- チャンネル一覧を更新
      local neo_slack = package.loaded['neo-slack']
      if neo_slack then
        neo_slack.list_channels()
      end
      notify('チャンネル「' .. channel.name .. '」を' ..
        (section.id and ('セクション「' .. section.name .. '」に割り当てました') or 'セクションから解除しました'),
        vim.log.levels.INFO)
    end
  end)
end

-- 現在の行のチャンネルをセクションに割り当て
function M.assign_channel_to_section_current()
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- チャンネルIDを直接取得（行番号から）
  local ok, channel_id = pcall(vim.api.nvim_buf_get_var, bufnr, 'channel_' .. line_nr)
  
  if ok and channel_id then
    M.assign_channel_dialog(channel_id)
  else
    notify('チャンネルを選択してください', vim.log.levels.ERROR)
  end
end

-- 現在の行のセクションを編集
function M.edit_section_current()
  local line = vim.api.nvim_get_current_line()
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- セクションヘッダーかどうかを判断
  if line:match('^## [▶▼]') then
    -- セクションIDを取得
    local ok, section_id = pcall(vim.api.nvim_buf_get_var, bufnr, 'section_' .. line_nr)
    
    if ok and section_id then
      M.edit_section_dialog(section_id)
    elseif line:match('★ スター付き') then
      notify('スター付きセクションは編集できません', vim.log.levels.WARN)
    elseif line:match('チャンネル$') then
      notify('デフォルトのチャンネルセクションは編集できません', vim.log.levels.WARN)
    end
  else
    notify('セクションヘッダーを選択してください', vim.log.levels.ERROR)
  end
end

-- 現在の行のセクションを削除
function M.delete_section_current()
  local line = vim.api.nvim_get_current_line()
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- セクションヘッダーかどうかを判断
  if line:match('^## [▶▼]') then
    -- セクションIDを取得
    local ok, section_id = pcall(vim.api.nvim_buf_get_var, bufnr, 'section_' .. line_nr)
    
    if ok and section_id then
      M.delete_section_dialog(section_id)
    elseif line:match('★ スター付き') then
      notify('スター付きセクションは削除できません', vim.log.levels.WARN)
    elseif line:match('チャンネル$') then
      notify('デフォルトのチャンネルセクションは削除できません', vim.log.levels.WARN)
    end
  else
    notify('セクションヘッダーを選択してください', vim.log.levels.ERROR)
  end
end

-- チャンネル一覧のキーマッピングを設定
---@param bufnr number バッファ番号
---@return nil
function M.setup_channels_keymaps(bufnr)
  local opts = { noremap = true, silent = true }
  
  -- Enter: チャンネルを選択またはセクションの折りたたみ/展開
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', '<cmd>lua require("neo-slack.ui").select_channel_or_toggle_section()<CR>', opts)
  
  -- q: ウィンドウを閉じる
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', '<cmd>q<CR>', opts)
  
  -- r: チャンネル一覧を更新
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'r', '<cmd>SlackChannels<CR>', opts)
  
  -- s: チャンネルをスター付き/解除
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 's', '<cmd>lua require("neo-slack.ui").toggle_star_channel()<CR>', opts)
  
  -- a: チャンネルをセクションに割り当て
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'a', '<cmd>lua require("neo-slack.ui").assign_channel_to_section_current()<CR>', opts)
  
  -- c: 新しいセクションを作成
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'c', '<cmd>lua require("neo-slack.ui").create_section_dialog()<CR>', opts)
  
  -- e: セクションを編集
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'e', '<cmd>lua require("neo-slack.ui").edit_section_current()<CR>', opts)
  
  -- d: セクションを削除
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'd', '<cmd>lua require("neo-slack.ui").delete_section_current()<CR>', opts)
end

-- メッセージ一覧のキーマッピングを設定
---@param bufnr number バッファ番号
---@return nil
function M.setup_messages_keymaps(bufnr)
  local opts = { noremap = true, silent = true }
  
  -- Enter: スレッドを開く
  vim.api.nvim_buf_set_keymap(bufnr, 'n', '<CR>', '<cmd>lua require("neo-slack.ui").open_thread()<CR>', opts)
  
  -- r: 返信
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'r', '<cmd>lua require("neo-slack.ui").reply_to_message()<CR>', opts)
  
  -- e: リアクション追加
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'e', '<cmd>lua require("neo-slack.ui").add_reaction_to_message()<CR>', opts)
  
  -- u: ファイルアップロード
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'u', '<cmd>lua require("neo-slack.ui").upload_file_to_channel()<CR>', opts)
  
  -- m: 新しいメッセージを送信
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'm', '<cmd>lua require("neo-slack.ui").send_new_message()<CR>', opts)
  
  -- R: メッセージ一覧を更新
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'R', '<cmd>lua require("neo-slack.ui").refresh_messages()<CR>', opts)
  
  -- q: ウィンドウを閉じる
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', '<cmd>q<CR>', opts)
end

-- スレッド一覧のキーマッピングを設定
---@param bufnr number バッファ番号
---@return nil
function M.setup_thread_keymaps(bufnr)
  local opts = { noremap = true, silent = true }
  
  -- r: スレッドに返信
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'r', '<cmd>lua require("neo-slack.ui").reply_to_thread()<CR>', opts)
  
  -- e: リアクション追加
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'e', '<cmd>lua require("neo-slack.ui").add_reaction_to_thread_message()<CR>', opts)
  
  -- R: スレッド一覧を更新
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'R', '<cmd>lua require("neo-slack.ui").refresh_thread()<CR>', opts)
  
  -- q: スレッドを閉じる
  vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', '<cmd>lua require("neo-slack.ui").close_thread()<CR>', opts)
end

--------------------------------------------------
-- チャンネル表示関連の関数
--------------------------------------------------

--- チャンネル一覧を表示
--- @param channels table[] チャンネルオブジェクトの配列
--- @return nil
function M.show_channels(channels)
  -- 分割レイアウトを設定
  M.setup_split_layout()
  
  -- バッファを作成または取得
  local bufnr = M.get_or_create_buffer('channels')
  M.layout.channels_buf = bufnr
  
  -- バッファを設定
  setup_buffer_options(bufnr, 'neo-slack-channels')
  
  -- セクションの折りたたみ状態を初期化（初回のみ）
  if not state.section_collapsed or not next(state.section_collapsed) then
    state.init_section_collapsed()
  end
  
  -- チャンネル一覧を整形
  local lines = {
    '# Slackチャンネル一覧',
    '',
  }
  
  -- チャンネルをセクションごとに分類
  local starred_channels = {}
  local normal_channels = {}
  local sectioned_channels = {}
  
  for _, channel in ipairs(channels) do
    local section_id = state.get_channel_section(channel.id)
    
    if state.is_channel_starred(channel.id) then
      table.insert(starred_channels, channel)
    elseif section_id then
      if not sectioned_channels[section_id] then
        sectioned_channels[section_id] = {}
      end
      table.insert(sectioned_channels[section_id], channel)
    else
      table.insert(normal_channels, channel)
    end
  end
  
  -- チャンネルをソート（それぞれのカテゴリ内でアルファベット順）
  local sort_func = function(a, b)
    return a.name < b.name
  end
  
  table.sort(starred_channels, sort_func)
  table.sort(normal_channels, sort_func)
  for _, channels_list in pairs(sectioned_channels) do
    table.sort(channels_list, sort_func)
  end
  
  -- スター付きチャンネルセクション
  if #starred_channels > 0 then
    -- 折りたたみ状態を表示
    local collapsed_mark = state.is_section_collapsed('starred') and '▶' or '▼'
    table.insert(lines, string.format('## %s ★ スター付き', collapsed_mark))
    
    -- 折りたたまれていない場合のみチャンネルを表示
    if not state.is_section_collapsed('starred') then
      for _, channel in ipairs(starred_channels) do
        local prefix = channel.is_private and '🔒' or '#'
        local member_status = channel.is_member and '✓' or ' '
        local has_unread = channel.unread_count and channel.unread_count > 0
        local unread = has_unread and string.format(' (%d)', channel.unread_count) or ''
        
        -- 未読があるチャンネルには "unread_" プレフィックスを追加、既読済みには "read_" プレフィックスを追加
        local read_status = has_unread and "unread_" or "read_"
        table.insert(lines, string.format('%s %s %s%s%s', read_status, member_status, prefix, channel.name, unread))
        
        -- チャンネルIDを保存（後で使用）
        vim.api.nvim_buf_set_var(bufnr, 'channel_' .. #lines, channel.id)
      end
      
      -- セクション間の区切り
      table.insert(lines, '')
    end
  end
  
  -- カスタムセクション
  local sorted_sections = {}
  for id, section in pairs(state.custom_sections) do
    table.insert(sorted_sections, section)
  end
  table.sort(sorted_sections, function(a, b) return a.order < b.order end)
  
  for _, section in ipairs(sorted_sections) do
    local section_channels = sectioned_channels[section.id] or {}
    if #section_channels > 0 then
      -- 折りたたみ状態を表示
      local collapsed_mark = state.is_section_collapsed(section.id) and '▶' or '▼'
      table.insert(lines, string.format('## %s %s', collapsed_mark, section.name))
      
      -- セクションIDを保存（後で使用）
      vim.api.nvim_buf_set_var(bufnr, 'section_' .. #lines, section.id)
      
      -- 折りたたまれていない場合のみチャンネルを表示
      if not state.is_section_collapsed(section.id) then
        for _, channel in ipairs(section_channels) do
          local prefix = channel.is_private and '🔒' or '#'
          local member_status = channel.is_member and '✓' or ' '
          local has_unread = channel.unread_count and channel.unread_count > 0
          local unread = has_unread and string.format(' (%d)', channel.unread_count) or ''
          
          -- 未読があるチャンネルには "unread_" プレフィックスを追加、既読済みには "read_" プレフィックスを追加
          local read_status = has_unread and "unread_" or "read_"
          table.insert(lines, string.format('%s %s %s %s%s', read_status, member_status, prefix, channel.name, unread))
          
          -- チャンネルIDを保存（後で使用）
          vim.api.nvim_buf_set_var(bufnr, 'channel_' .. #lines, channel.id)
        end
        
        -- セクション間の区切り
        table.insert(lines, '')
      end
    end
  end
  
  -- 通常のチャンネルセクション
  -- 折りたたみ状態を表示
  local collapsed_mark = state.is_section_collapsed('channels') and '▶' or '▼'
  table.insert(lines, string.format('## %s チャンネル', collapsed_mark))
  
  -- 折りたたまれていない場合のみチャンネルを表示
  if not state.is_section_collapsed('channels') then
    for _, channel in ipairs(normal_channels) do
      local prefix = channel.is_private and '🔒' or '#'
      local member_status = channel.is_member and '✓' or ' '
      local has_unread = channel.unread_count and channel.unread_count > 0
      local unread = has_unread and string.format(' (%d)', channel.unread_count) or ''
      
      -- 未読があるチャンネルには "unread_" プレフィックスを追加、既読済みには "read_" プレフィックスを追加
      local read_status = has_unread and "unread_" or "read_"
      table.insert(lines, string.format('%s %s %s %s%s', read_status, member_status, prefix, channel.name, unread))
      
      -- チャンネルIDを保存（後で使用）
      vim.api.nvim_buf_set_var(bufnr, 'channel_' .. #lines, channel.id)
    end
  end
  
  -- バッファにラインを設定
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  
  -- キーマッピングを設定
  M.setup_channels_keymaps(bufnr)
  
  -- 左側のウィンドウにバッファを表示
  vim.api.nvim_win_set_buf(M.layout.channels_win, bufnr)
  
  -- チャンネル一覧のウィンドウにフォーカス
  vim.api.nvim_set_current_win(M.layout.channels_win)
end

--- チャンネル名を取得
--- @param channel_id string チャンネルID
--- @return string チャンネル名
local function get_channel_name(channel_id)
  -- 状態からチャンネル情報を取得
  local channel = state.get_channel_by_id(channel_id)
  if channel and channel.name then
    return channel.name
  end
  
  -- チャンネル情報がない場合はIDをそのまま返す
  return channel_id
end

--------------------------------------------------
-- メッセージ表示関連の関数
--------------------------------------------------

--- メッセージヘッダーを作成
--- @param message table メッセージオブジェクト
--- @param user_message_lines table ユーザー名とメッセージ行の対応を保存するテーブル
--- @param lines table[] 行の配列
--- @return nil
local function create_message_header(message, user_message_lines, lines)
  -- 一時的にユーザーIDを表示（後で置き換える）
  local user_id = message.user or 'unknown'
  
  -- 日時をフォーマット
  local timestamp = utils.format_timestamp(message.ts)
  
  -- メッセージヘッダー行のインデックスを記録
  local header_line_index = #lines + 1
  
  -- メッセージヘッダー
  table.insert(lines, string.format('### %s (%s)', user_id, timestamp))
  
  -- ユーザーIDと行番号の対応を保存
  if user_id ~= 'unknown' then
    if not user_message_lines[user_id] then
      user_message_lines[user_id] = {}
    end
    table.insert(user_message_lines[user_id], header_line_index)
  end
end

--- メッセージ本文を作成
--- @param message table メッセージオブジェクト
--- @param lines table[] 行の配列
--- @return nil
local function create_message_body(message, lines)
  -- メッセージ本文（複数行に対応）
  local text_lines = utils.split_lines(message.text)
  for _, line in ipairs(text_lines) do
    table.insert(lines, line)
  end
  
  -- リアクション
  if message.reactions and #message.reactions > 0 then
    local reactions = {}
    for _, reaction in ipairs(message.reactions) do
      table.insert(reactions, string.format(':%s: %d', reaction.name, reaction.count))
    end
    table.insert(lines, '> ' .. table.concat(reactions, ' '))
  end
  
  -- スレッド情報
  if message.thread_ts and message.reply_count and message.reply_count > 0 then
    table.insert(lines, string.format('> スレッド返信: %d件', message.reply_count))
  end
end

--- メッセージ一覧を表示
--- @param channel string チャンネル名またはID
--- @param messages table[] メッセージオブジェクトの配列
--- @return nil
function M.show_messages(channel, messages)
  -- 分割レイアウトを設定
  M.setup_split_layout()
  
  -- チャンネル名を取得
  local channel_name = channel
  if channel:match('^[A-Z0-9]+$') then
    channel_name = get_channel_name(channel)
  end
  
  -- バッファを作成または取得
  local bufnr = M.get_or_create_buffer('messages_' .. channel)
  M.layout.messages_buf = bufnr
  
  -- 現在のチャンネルIDを状態に保存
  state.set_current_channel(channel, channel_name)
  
  -- バッファを設定
  setup_buffer_options(bufnr, 'neo-slack-messages')
  
  -- メッセージ一覧を整形
  local lines = {
    '# ' .. channel_name .. ' のメッセージ',
    '',
  }
  
  -- メッセージを時系列順にソート
  table.sort(messages, function(a, b)
    return tonumber(a.ts) < tonumber(b.ts)
  end)
  
  -- ユーザー名とメッセージ行の対応を保存するテーブル
  local user_message_lines = {}
  
  -- メッセージ情報を追加
  for _, message in ipairs(messages) do
    -- メッセージヘッダーを作成
    create_message_header(message, user_message_lines, lines)
    
    -- メッセージ本文を作成
    create_message_body(message, lines)
    
    -- メッセージIDを保存（後で使用）
    vim.api.nvim_buf_set_var(bufnr, 'message_' .. #lines, message.ts)
    
    -- 区切り線
    table.insert(lines, '')
    table.insert(lines, '---')
    table.insert(lines, '')
  end
  
  -- バッファにラインを設定
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  
  -- キーマッピングを設定
  M.setup_messages_keymaps(bufnr)
  
  -- 右側のウィンドウにバッファを表示
  vim.api.nvim_win_set_buf(M.layout.messages_win, bufnr)
  
  -- メッセージ一覧のウィンドウにフォーカス
  vim.api.nvim_set_current_win(M.layout.messages_win)
  
  -- 非同期でユーザー名を取得して表示を更新
  M.update_usernames(bufnr, user_message_lines)
end

--- スレッド返信一覧を表示
--- @param thread_ts string スレッドの親メッセージのタイムスタンプ
--- @param replies table[] 返信メッセージの配列
--- @param parent_message table 親メッセージオブジェクト
--- @return nil
function M.show_thread_replies(thread_ts, replies, parent_message)
  -- 3分割レイアウトを設定
  M.setup_thread_layout()
  
  -- バッファを作成または取得
  local bufnr = M.get_or_create_buffer('thread_' .. thread_ts)
  M.layout.thread_buf = bufnr
  
  -- バッファを設定
  setup_buffer_options(bufnr, 'neo-slack-messages')
  
  -- スレッド一覧を整形
  local lines = {
    '# スレッド返信',
    '',
  }
  
  -- ユーザー名とメッセージ行の対応を保存するテーブル
  local user_message_lines = {}
  
  -- 親メッセージを表示
  if parent_message then
    -- メッセージヘッダーを作成
    create_message_header(parent_message, user_message_lines, lines)
    
    -- メッセージ本文を作成
    create_message_body(parent_message, lines)
    
    -- メッセージIDを保存（後で使用）
    vim.api.nvim_buf_set_var(bufnr, 'message_' .. #lines, parent_message.ts)
    
    -- 区切り線
    table.insert(lines, '')
    table.insert(lines, '---')
    table.insert(lines, '')
  end
  
  -- 返信メッセージを時系列順にソート
  table.sort(replies, function(a, b)
    return tonumber(a.ts) < tonumber(b.ts)
  end)
  
  -- 返信メッセージを表示
  for _, message in ipairs(replies) do
    -- メッセージヘッダーを作成
    create_message_header(message, user_message_lines, lines)
    
    -- メッセージ本文を作成
    create_message_body(message, lines)
    
    -- メッセージIDを保存（後で使用）
    vim.api.nvim_buf_set_var(bufnr, 'message_' .. #lines, message.ts)
    
    -- 区切り線
    table.insert(lines, '')
    table.insert(lines, '---')
    table.insert(lines, '')
  end
  
  -- バッファにラインを設定
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  
  -- キーマッピングを設定
  M.setup_thread_keymaps(bufnr)
  
  -- スレッドウィンドウにバッファを表示
  vim.api.nvim_win_set_buf(M.layout.thread_win, bufnr)
  
  -- スレッドウィンドウにフォーカス
  vim.api.nvim_set_current_win(M.layout.thread_win)
  
  -- 非同期でユーザー名を取得して表示を更新
  M.update_usernames(bufnr, user_message_lines)
end

--- ユーザー名を非同期で更新
--- @param bufnr number バッファ番号
--- @param user_message_lines table ユーザー名とメッセージ行の対応を保存するテーブル
--- @return nil
function M.update_usernames(bufnr, user_message_lines)
  for user_id, line_indices in pairs(user_message_lines) do
    api.get_username(user_id, function(username)
      -- バッファが存在するか確認
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      
      -- バッファを編集可能に設定
      vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
      
      -- 各行を更新
      for _, line_idx in ipairs(line_indices) do
        -- 現在の行を取得
        local line = vim.api.nvim_buf_get_lines(bufnr, line_idx - 1, line_idx, false)[1]
        
        -- ユーザーIDをユーザー名に置き換え（正規表現のメタ文字をエスケープ）
        local escaped_user_id = user_id:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        local new_line = line:gsub(escaped_user_id, username)
        
        -- 行を更新
        vim.api.nvim_buf_set_lines(bufnr, line_idx - 1, line_idx, false, {new_line})
      end
      
      -- バッファを編集不可に戻す
      vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
    end)
  end
end

--------------------------------------------------
-- ユーザーインタラクション関連の関数
--------------------------------------------------

--- 現在の行からメッセージIDを取得
--- @param line_nr number|nil 行番号（nilの場合は現在の行）
--- @return string|nil メッセージID
local function get_message_ts_at_line(line_nr)
  line_nr = line_nr or vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- 現在の行から上に遡って、メッセージIDを探す
  for i = line_nr, 1, -1 do
    local ok, ts = pcall(vim.api.nvim_buf_get_var, bufnr, 'message_' .. i)
    if ok then
      return ts
    end
  end
  
  return nil
end

--- チャンネルを選択またはセクションの折りたたみ/展開
--- @return nil
function M.select_channel_or_toggle_section()
  local line = vim.api.nvim_get_current_line()
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- セクションヘッダーかどうかを判断（折りたたみマーク付き）
  if line:match('^## [▶▼]') then
    -- カスタムセクションのIDを取得
    local ok, section_id = pcall(vim.api.nvim_buf_get_var, bufnr, 'section_' .. line_nr)
    
    if ok and section_id then
      -- カスタムセクションの折りたたみ/展開
      M.toggle_section_collapse(section_id)
      return
    elseif line:match('★ スター付き') then
      -- スター付きセクションの折りたたみ/展開
      M.toggle_section_collapse('starred')
      return
    elseif line:match('チャンネル$') then
      -- チャンネルセクションの折りたたみ/展開
      M.toggle_section_collapse('channels')
      return
    end
  end
  
  -- セクションヘッダーでない場合はチャンネルを選択
  M.select_channel()
end

--- チャンネルを選択
--- @return nil
function M.select_channel()
  local line = vim.api.nvim_get_current_line()
  -- "unread_" または "read_" プレフィックスを削除
  line = line:gsub("^unread_", ""):gsub("^read_", "")
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- チャンネルIDを直接取得（行番号から）
  local ok, channel_id = pcall(vim.api.nvim_buf_get_var, bufnr, 'channel_' .. line_nr)
  
  if ok and channel_id then
    -- チャンネル名を抽出（表示用）
    local channel_name = line:match('[#🔒]%s+([%w-_]+)')
    if not channel_name then
      channel_name = "選択したチャンネル"
    end
    
    notify(channel_name .. ' を選択しました', vim.log.levels.INFO)
    
    -- 状態に現在のチャンネルを設定
    state.set_current_channel(channel_id, channel_name)
    
    -- チャンネルのメッセージを表示（右側のウィンドウに）
    -- 循環参照を避けるため、package.loadedを使用
    local neo_slack = package.loaded['neo-slack']
    if neo_slack then
      neo_slack.select_channel(channel_id, channel_name)
    end
    
    -- メッセージ一覧のウィンドウにフォーカス
    vim.api.nvim_set_current_win(M.layout.messages_win)
  else
    -- 従来の方法でチャンネル名を抽出（"unread_" または "read_" プレフィックスを考慮）
    local channel_name = line:match('[✓%s][#🔒]%s+([%w-_]+)')
    
    if not channel_name then
      notify('チャンネルを選択できませんでした', vim.log.levels.ERROR)
      return
    end
    -- チャンネルのメッセージを表示
    -- 循環参照を避けるため、package.loadedを使用
    local neo_slack = package.loaded['neo-slack']
    if neo_slack then
      neo_slack.list_messages(channel_name)
    end
    
    
    -- メッセージ一覧のウィンドウにフォーカス
    vim.api.nvim_set_current_win(M.layout.messages_win)
  end
end

--- スレッドを開く
--- @return nil
function M.open_thread()
  local line = vim.api.nvim_get_current_line()
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  
  -- スレッド返信の行を探す
  if not line:match('> スレッド返信:') then
    -- 現在の行からメッセージIDを取得
    local message_ts = get_message_ts_at_line()
    if message_ts then
      -- メッセージがスレッドの親かどうかを確認
      local channel_id = state.get_current_channel()
      local messages = state.get_messages(channel_id)
      for _, message in ipairs(messages) do
        if message.ts == message_ts and message.thread_ts and message.reply_count and message.reply_count > 0 then
          -- スレッド返信を表示
          -- 循環参照を避けるため、package.loadedを使用
          local neo_slack = package.loaded['neo-slack']
          if neo_slack then
            neo_slack.list_thread_replies(message_ts)
          end
          return
        end
      end
      notify('このメッセージにはスレッド返信がありません', vim.log.levels.INFO)
    else
      notify('スレッドを開くメッセージが見つかりませんでした', vim.log.levels.ERROR)
    end
    return
  end
  
  -- スレッド返信の行から親メッセージのIDを取得
  for i = line_nr, 1, -1 do
    local ok, ts = pcall(vim.api.nvim_buf_get_var, vim.api.nvim_get_current_buf(), 'message_' .. i)
    if ok then
      -- スレッド返信を表示
      -- 循環参照を避けるため、package.loadedを使用
      local neo_slack = package.loaded['neo-slack']
      if neo_slack then
        neo_slack.list_thread_replies(ts)
      end
      return
    end
  end
  
  notify('スレッドを開くメッセージが見つかりませんでした', vim.log.levels.ERROR)
end

--- スレッドを閉じる
--- @return nil
function M.close_thread()
  -- スレッドウィンドウが存在する場合は閉じる
  if M.layout.thread_win and vim.api.nvim_win_is_valid(M.layout.thread_win) then
    vim.api.nvim_win_close(M.layout.thread_win, true)
    M.layout.thread_win = nil
    M.layout.thread_buf = nil
    
    -- 状態からスレッド情報をクリア
    state.set_current_thread(nil, nil)
    
    -- メッセージ一覧のウィンドウにフォーカス
    vim.api.nvim_set_current_win(M.layout.messages_win)
    
    notify('スレッドを閉じました', vim.log.levels.INFO)
  end
end

--- メッセージに返信
--- @return nil
function M.reply_to_message()
  local message_ts = get_message_ts_at_line()
  
  if not message_ts then
    notify('返信するメッセージが見つかりませんでした', vim.log.levels.ERROR)
    return
  end
  
  -- 返信入力を促す
  vim.ui.input({ prompt = '返信: ' }, function(input)
    if input and input ~= '' then
      -- 循環参照を避けるため、package.loadedを使用
      local neo_slack = package.loaded['neo-slack']
      if neo_slack then
        neo_slack.reply_message(message_ts, input)
      end
    end
  end)
end

--- スレッドに返信
--- @return nil
function M.reply_to_thread()
  local message_ts = get_message_ts_at_line()
  
  if not message_ts then
    notify('返信するメッセージが見つかりませんでした', vim.log.levels.ERROR)
    return
  end
  
  -- 現在のスレッドのタイムスタンプを取得
  local thread_ts = state.get_current_thread()
  
  -- スレッドの親メッセージに返信
  local reply_ts = thread_ts or message_ts
  
  -- 返信入力を促す
  vim.ui.input({ prompt = 'スレッド返信: ' }, function(input)
    if input and input ~= '' then
      -- 循環参照を避けるため、package.loadedを使用
      local neo_slack = package.loaded['neo-slack']
      if neo_slack then
        neo_slack.reply_to_thread(reply_ts, input)
      end
    end
  end)
end

--- メッセージにリアクションを追加
--- @return nil
function M.add_reaction_to_message()
  local message_ts = get_message_ts_at_line()
  
  if not message_ts then
    notify('リアクションを追加するメッセージが見つかりませんでした', vim.log.levels.ERROR)
    return
  end
  
  -- リアクション入力を促す
  vim.ui.input({ prompt = 'リアクション (例: thumbsup): ' }, function(input)
    if input and input ~= '' then
      -- 循環参照を避けるため、package.loadedを使用
      local neo_slack = package.loaded['neo-slack']
      if neo_slack then
        neo_slack.add_reaction(message_ts, input)
      end
    end
  end)
end

--- スレッドメッセージにリアクションを追加
--- @return nil
function M.add_reaction_to_thread_message()
  local message_ts = get_message_ts_at_line()
  
  if not message_ts then
    notify('リアクションを追加するメッセージが見つかりませんでした', vim.log.levels.ERROR)
    return
  end
  
  -- リアクション入力を促す
  vim.ui.input({ prompt = 'リアクション (例: thumbsup): ' }, function(input)
    if input and input ~= '' then
      -- 循環参照を避けるため、package.loadedを使用
      local neo_slack = package.loaded['neo-slack']
      if neo_slack then
        neo_slack.add_reaction(message_ts, input)
      end
    end
  end)
end

--- チャンネルにファイルをアップロード
--- @return nil
function M.upload_file_to_channel()
  local channel_id = state.get_current_channel()
  
  if not channel_id then
    notify('チャンネルが選択されていません', vim.log.levels.ERROR)
    return
  end
  
  -- ファイルパス入力を促す
  vim.ui.input({ prompt = 'アップロードするファイルパス: ' }, function(input)
    if input and input ~= '' then
      -- 循環参照を避けるため、package.loadedを使用
      local neo_slack = package.loaded['neo-slack']
      if neo_slack then
        neo_slack.upload_file(channel_id, input)
      end
    end
  end)
end

--- メッセージ一覧を更新
--- @return nil
function M.refresh_messages()
  local channel_id = state.get_current_channel()
  
  if not channel_id then
    notify('チャンネルが選択されていません', vim.log.levels.ERROR)
    return
  end
  
  -- 循環参照を避けるため、package.loadedを使用
  local neo_slack = package.loaded['neo-slack']
  if neo_slack then
    neo_slack.list_messages(channel_id)
  end
end

--- スレッド一覧を更新
--- @return nil
function M.refresh_thread()
  local thread_ts = state.get_current_thread()
  
  if not thread_ts then
    notify('スレッドが選択されていません', vim.log.levels.ERROR)
    return
  end
  
  -- 循環参照を避けるため、package.loadedを使用
  local neo_slack = package.loaded['neo-slack']
  if neo_slack then
    neo_slack.list_thread_replies(thread_ts)
  end
end

--- 新しいメッセージを送信
--- @return nil
function M.send_new_message()
  local channel_id = state.get_current_channel()
  
  if not channel_id then
    notify('チャンネルが選択されていません', vim.log.levels.ERROR)
    return
  end
  
  -- メッセージ入力を促す
  vim.ui.input({ prompt = 'メッセージ: ' }, function(input)
    if input and input ~= '' then
      -- 循環参照を避けるため、package.loadedを使用
      local neo_slack = package.loaded['neo-slack']
      if neo_slack then
        neo_slack.send_message(channel_id, input)
      end
    end
  end)
end

--- チャンネルをスター付き/解除
--- @return nil
function M.toggle_star_channel()
  local line = vim.api.nvim_get_current_line()
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- チャンネルIDを直接取得（行番号から）
  local ok, channel_id = pcall(vim.api.nvim_buf_get_var, bufnr, 'channel_' .. line_nr)
  
  if ok and channel_id then
    -- チャンネル名を抽出（表示用）
    local channel_name = line:match('[#🔒]%s+([%w-_]+)')
    if not channel_name then
      channel_name = "選択したチャンネル"
    end
    
    -- スター付き状態を切り替え
    local is_starred = state.is_channel_starred(channel_id)
    state.set_channel_starred(channel_id, not is_starred)
    -- スター付きチャンネルを保存
    state.save_starred_channels()
    storage.save_starred_channels(state.starred_channels)
    
    -- 通知
    if not is_starred then
      notify(channel_name .. ' をスター付きに追加しました', vim.log.levels.INFO)
    else
      notify(channel_name .. ' のスターを解除しました', vim.log.levels.INFO)
    end
    
    -- チャンネル一覧を更新
    -- 循環参照を避けるため、package.loadedを使用
    local neo_slack = package.loaded['neo-slack']
    if neo_slack then
      neo_slack.list_channels()
    end
  else
    notify('チャンネルを選択できませんでした', vim.log.levels.ERROR)
  end
end

return M
