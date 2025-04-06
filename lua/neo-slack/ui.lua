---@brief [[
--- neo-slack UI モジュール
--- ユーザーインターフェースを処理します
---@brief ]]

local api = require('neo-slack.api')
local utils = require('neo-slack.utils')

---@class NeoSlackUI
local M = {}

-- バッファ名の接頭辞
M.buffer_prefix = 'neo-slack://'

-- 現在のバッファ情報
M.buffers = {
  channels = nil,
  messages = {},
}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
local function notify(message, level)
  utils.notify(message, level)
end

-- バッファオプションを設定
---@param bufnr number バッファ番号
---@param filetype string ファイルタイプ
local function setup_buffer_options(bufnr, filetype)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_option(bufnr, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(bufnr, 'swapfile', false)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', filetype)
end

-- チャンネル一覧を表示
---@param channels table[] チャンネルオブジェクトの配列
function M.show_channels(channels)
  -- バッファを作成または取得
  local bufnr = M.get_or_create_buffer('channels')
  
  -- バッファを設定
  setup_buffer_options(bufnr, 'neo-slack-channels')
  
  -- チャンネル一覧を整形
  local lines = {
    '# Slackチャンネル一覧',
    '',
  }
  
  -- チャンネルをソート
  table.sort(channels, function(a, b)
    return a.name < b.name
  end)
  
  -- チャンネル情報を追加
  for _, channel in ipairs(channels) do
    local prefix = channel.is_private and '🔒' or '#'
    local member_status = channel.is_member and '✓' or ' '
    local unread = channel.unread_count and channel.unread_count > 0
      and string.format(' (%d)', channel.unread_count) or ''
    
    table.insert(lines, string.format('%s %s %s%s', member_status, prefix, channel.name, unread))
    
    -- チャンネルIDを保存（後で使用）
    vim.api.nvim_buf_set_var(bufnr, 'channel_' .. #lines, channel.id)
  end
  
  -- バッファにラインを設定
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
  
  -- キーマッピングを設定
  M.setup_channels_keymaps(bufnr)
  
  -- バッファを表示
  vim.cmd('buffer ' .. bufnr)
end

-- チャンネル名を取得
---@param channel_id string チャンネルID
---@return string チャンネル名
local function get_channel_name(channel_id)
  -- IDからチャンネル名を取得する処理
  -- 実際の実装では、APIからチャンネル名を取得する必要があります
  -- 現在は簡略化のためにIDをそのまま返す
  return channel_id
end

-- メッセージ一覧を表示
---@param channel string チャンネル名またはID
---@param messages table[] メッセージオブジェクトの配列
function M.show_messages(channel, messages)
  -- チャンネル名を取得
  local channel_name = channel
  if channel:match('^[A-Z0-9]+$') then
    channel_name = get_channel_name(channel)
  end
  
  -- バッファを作成または取得
  local bufnr = M.get_or_create_buffer('messages_' .. channel)
  
  -- 現在のチャンネルIDをグローバル変数に保存
  vim.g.neo_slack_current_channel_id = channel
  
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
  
  -- バッファを表示
  vim.cmd('buffer ' .. bufnr)
  
  -- 非同期でユーザー名を取得して表示を更新
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

-- バッファを取得または作成
---@param name string バッファ名
---@return number バッファ番号
function M.get_or_create_buffer(name)
  local full_name = M.buffer_prefix .. name
  
  -- 既存のバッファを検索
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local buf_name = vim.api.nvim_buf_get_name(bufnr)
    if buf_name == full_name then
      return bufnr
    end
  end
  
  -- 新しいバッファを作成
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, full_name)
  
  -- バッファ情報を保存
  if name == 'channels' then
    M.buffers.channels = bufnr
  elseif name:match('^messages_') then
    local channel = name:gsub('^messages_', '')
    M.buffers.messages[channel] = bufnr
  end
  
  return bufnr
end

-- キーマッピングを設定
---@param bufnr number バッファ番号
---@param mode string モード ('n', 'i', 'v', etc.)
---@param key string キー
---@param cmd string コマンド
---@param opts table|nil オプション
local function set_keymap(bufnr, mode, key, cmd, opts)
  opts = opts or { noremap = true, silent = true }
  vim.api.nvim_buf_set_keymap(bufnr, mode, key, cmd, opts)
end

-- チャンネル一覧のキーマッピングを設定
---@param bufnr number バッファ番号
function M.setup_channels_keymaps(bufnr)
  local opts = { noremap = true, silent = true }
  
  -- Enter: チャンネルを選択
  set_keymap(bufnr, 'n', '<CR>', [[<cmd>lua require('neo-slack.ui').select_channel()<CR>]], opts)
  
  -- r: チャンネル一覧を更新
  set_keymap(bufnr, 'n', 'r', [[<cmd>lua require('neo-slack').list_channels()<CR>]], opts)
  
  -- q: バッファを閉じる
  set_keymap(bufnr, 'n', 'q', [[<cmd>bdelete<CR>]], opts)
end

-- メッセージ一覧のキーマッピングを設定
---@param bufnr number バッファ番号
function M.setup_messages_keymaps(bufnr)
  local opts = { noremap = true, silent = true }
  
  -- r: 返信モード
  set_keymap(bufnr, 'n', 'r', [[<cmd>lua require('neo-slack.ui').reply_to_message()<CR>]], opts)
  
  -- e: リアクション追加
  set_keymap(bufnr, 'n', 'e', [[<cmd>lua require('neo-slack.ui').add_reaction_to_message()<CR>]], opts)
  
  -- u: ファイルアップロード
  set_keymap(bufnr, 'n', 'u', [[<cmd>lua require('neo-slack.ui').upload_file_to_channel()<CR>]], opts)
  
  -- R: メッセージ一覧を更新
  set_keymap(bufnr, 'n', 'R', [[<cmd>lua require('neo-slack.ui').refresh_messages()<CR>]], opts)
  
  -- q: バッファを閉じる
  set_keymap(bufnr, 'n', 'q', [[<cmd>bdelete<CR>]], opts)
  
  -- m: 新しいメッセージを送信
  set_keymap(bufnr, 'n', 'm', [[<cmd>lua require('neo-slack.ui').send_new_message()<CR>]], opts)
end

-- 現在の行からメッセージIDを取得
---@param line_nr number|nil 行番号（nilの場合は現在の行）
---@return string|nil メッセージID
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

-- チャンネルを選択
function M.select_channel()
  local line = vim.api.nvim_get_current_line()
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- チャンネルIDを直接取得（行番号から）
  local ok, channel_id = pcall(vim.api.nvim_buf_get_var, bufnr, 'channel_' .. line_nr)
  
  if ok and channel_id then
    -- チャンネルIDを直接使用
    vim.g.neo_slack_current_channel_id = channel_id
    
    -- チャンネル名を抽出（表示用）
    local channel_name = line:match('[#🔒]%s+([%w-_]+)')
    if not channel_name then
      channel_name = "選択したチャンネル"
    end
    
    notify(channel_name .. ' を選択しました', vim.log.levels.INFO)
    
    -- チャンネルのメッセージを表示
    require('neo-slack').list_messages(channel_id)
  else
    -- 従来の方法でチャンネル名を抽出
    local channel_name = line:match('[✓%s][#🔒]%s+([%w-_]+)')
    
    if not channel_name then
      notify('チャンネルを選択できませんでした', vim.log.levels.ERROR)
      return
    end
    
    -- チャンネルのメッセージを表示
    require('neo-slack').list_messages(channel_name)
  end
end

-- メッセージに返信
function M.reply_to_message()
  local message_ts = get_message_ts_at_line()
  
  if not message_ts then
    notify('返信するメッセージが見つかりませんでした', vim.log.levels.ERROR)
    return
  end
  
  -- 返信入力を促す
  vim.ui.input({ prompt = '返信: ' }, function(input)
    if input and input ~= '' then
      require('neo-slack').reply_message(message_ts, input)
    end
  end)
end

-- メッセージにリアクションを追加
function M.add_reaction_to_message()
  local message_ts = get_message_ts_at_line()
  
  if not message_ts then
    notify('リアクションを追加するメッセージが見つかりませんでした', vim.log.levels.ERROR)
    return
  end
  
  -- リアクション入力を促す
  vim.ui.input({ prompt = 'リアクション (例: thumbsup): ' }, function(input)
    if input and input ~= '' then
      require('neo-slack').add_reaction(message_ts, input)
    end
  end)
end

-- チャンネルにファイルをアップロード
function M.upload_file_to_channel()
  local channel = vim.g.neo_slack_current_channel_id
  
  if not channel then
    notify('チャンネルが選択されていません', vim.log.levels.ERROR)
    return
  end
  
  -- ファイルパス入力を促す
  vim.ui.input({ prompt = 'アップロードするファイルパス: ' }, function(input)
    if input and input ~= '' then
      require('neo-slack').upload_file(channel, input)
    end
  end)
end

-- メッセージ一覧を更新
function M.refresh_messages()
  local channel = vim.g.neo_slack_current_channel_id
  
  if not channel then
    notify('チャンネルが選択されていません', vim.log.levels.ERROR)
    return
  end
  
  require('neo-slack').list_messages(channel)
end

-- 新しいメッセージを送信
function M.send_new_message()
  local channel = vim.g.neo_slack_current_channel_id
  
  if not channel then
    notify('チャンネルが選択されていません', vim.log.levels.ERROR)
    return
  end
  
  -- メッセージ入力を促す
  vim.ui.input({ prompt = 'メッセージ: ' }, function(input)
    if input and input ~= '' then
      require('neo-slack').send_message(channel, input)
    end
  end)
end

return M