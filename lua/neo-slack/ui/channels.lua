---@brief [[
--- neo-slack.nvim UI チャンネルモジュール
--- チャンネル一覧の表示と操作を担当します
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_api() return dependency.get('api') end
local function get_utils() return dependency.get('utils') end
local function get_state() return dependency.get('state') end
local function get_events() return dependency.get('core.events') end
local function get_layout() return dependency.get('ui.layout') end

---@class NeoSlackUIChannels
local M = {}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
local function notify(message, level, opts)
  opts = opts or {}
  opts.prefix = 'UI Channels: '
  get_utils().notify(message, level, opts)
end

-- チャンネル一覧を表示
---@param channels table[] チャンネルオブジェクトの配列
function M.show_channels(channels)
  notify('UIにチャンネル一覧を表示します: ' .. (channels and #channels or 0) .. '件', vim.log.levels.INFO)

  local layout = get_layout()
  if not layout.layout.channels_buf or not vim.api.nvim_buf_is_valid(layout.layout.channels_buf) then
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
  vim.api.nvim_buf_set_option(layout.layout.channels_buf, 'modifiable', true)

  -- バッファをクリア
  vim.api.nvim_buf_set_lines(layout.layout.channels_buf, 0, -1, false, {})

  -- 行とチャンネルIDのマッピング
  local line_to_channel = {}
  local line_to_section = {}
  local current_line = 0

  -- スター付きセクション
  local starred_collapsed = get_state().is_section_collapsed('starred')
  table.insert(line_to_section, { line = current_line, id = 'starred', name = 'スター付き' })
  vim.api.nvim_buf_set_lines(layout.layout.channels_buf, current_line, current_line + 1, false, {'▼ スター付き'})
  current_line = current_line + 1

  if not starred_collapsed and #starred_channels > 0 then
    for _, channel in ipairs(starred_channels) do
      local prefix = channel.is_channel and '#' or (channel.is_private or channel.is_group) and '🔒' or (channel.is_im) and '@' or '👥'
      local name = channel.name or 'unknown'
      vim.api.nvim_buf_set_lines(layout.layout.channels_buf, current_line, current_line + 1, false, {'  ' .. prefix .. ' ' .. name})
      line_to_channel[current_line] = channel.id
      current_line = current_line + 1
    end
  end

  -- カスタムセクション
  for id, section in pairs(custom_sections) do
    if #section.channels > 0 then
      local collapsed_mark = section.is_collapsed and '▶' or '▼'
      table.insert(line_to_section, { line = current_line, id = id, name = section.name })
      vim.api.nvim_buf_set_lines(layout.layout.channels_buf, current_line, current_line + 1, false, {collapsed_mark .. ' ' .. section.name})
      current_line = current_line + 1

      if not section.is_collapsed then
        for _, channel in ipairs(section.channels) do
          local prefix = channel.is_channel and '#' or (channel.is_private or channel.is_group) and '🔒' or (channel.is_im) and '@' or '👥'
          local name = channel.name or 'unknown'
          vim.api.nvim_buf_set_lines(layout.layout.channels_buf, current_line, current_line + 1, false, {'  ' .. prefix .. ' ' .. name})
          line_to_channel[current_line] = channel.id
          current_line = current_line + 1
        end
      end
    end
  end

  -- チャンネルセクション
  local channels_collapsed = get_state().is_section_collapsed('channels')
  table.insert(line_to_section, { line = current_line, id = 'channels', name = 'チャンネル' })
  vim.api.nvim_buf_set_lines(layout.layout.channels_buf, current_line, current_line + 1, false, {(channels_collapsed and '▶' or '▼') .. ' チャンネル'})
  current_line = current_line + 1

  if not channels_collapsed then
    for _, channel in ipairs(public_channels) do
      vim.api.nvim_buf_set_lines(layout.layout.channels_buf, current_line, current_line + 1, false, {'  # ' .. channel.name})
      line_to_channel[current_line] = channel.id
      current_line = current_line + 1
    end
  end

  -- プライベートチャンネルセクション
  if #private_channels > 0 then
    local private_collapsed = get_state().is_section_collapsed('private')
    table.insert(line_to_section, { line = current_line, id = 'private', name = 'プライベートチャンネル' })
    vim.api.nvim_buf_set_lines(layout.layout.channels_buf, current_line, current_line + 1, false, {(private_collapsed and '▶' or '▼') .. ' プライベートチャンネル'})
    current_line = current_line + 1

    if not private_collapsed then
      for _, channel in ipairs(private_channels) do
        vim.api.nvim_buf_set_lines(layout.layout.channels_buf, current_line, current_line + 1, false, {'  🔒 ' .. channel.name})
        line_to_channel[current_line] = channel.id
        current_line = current_line + 1
      end
    end
  end

  -- DMセクション
  if #direct_messages > 0 then
    local dm_collapsed = get_state().is_section_collapsed('dm')
    table.insert(line_to_section, { line = current_line, id = 'dm', name = 'ダイレクトメッセージ' })
    vim.api.nvim_buf_set_lines(layout.layout.channels_buf, current_line, current_line + 1, false, {(dm_collapsed and '▶' or '▼') .. ' ダイレクトメッセージ'})
    current_line = current_line + 1

    if not dm_collapsed then
      for _, channel in ipairs(direct_messages) do
        local name = channel.name or 'unknown-user'
        vim.api.nvim_buf_set_lines(layout.layout.channels_buf, current_line, current_line + 1, false, {'  @ ' .. name})
        line_to_channel[current_line] = channel.id
        current_line = current_line + 1
      end
    end
  end

  -- グループメッセージセクション
  if #group_messages > 0 then
    local group_collapsed = get_state().is_section_collapsed('group')
    table.insert(line_to_section, { line = current_line, id = 'group', name = 'グループメッセージ' })
    vim.api.nvim_buf_set_lines(layout.layout.channels_buf, current_line, current_line + 1, false, {(group_collapsed and '▶' or '▼') .. ' グループメッセージ'})
    current_line = current_line + 1

    if not group_collapsed then
      for _, channel in ipairs(group_messages) do
        local name = channel.name or 'unknown-group'
        vim.api.nvim_buf_set_lines(layout.layout.channels_buf, current_line, current_line + 1, false, {'  👥 ' .. name})
        line_to_channel[current_line] = channel.id
        current_line = current_line + 1
      end
    end
  end

  -- バッファを編集不可に設定
  vim.api.nvim_buf_set_option(layout.layout.channels_buf, 'modifiable', false)

  -- 行とチャンネルIDのマッピングを保存
  layout.layout.line_to_channel = line_to_channel
  layout.layout.line_to_section = line_to_section

  -- 現在のチャンネルをハイライト
  M.highlight_current_channel()
end

-- 現在のチャンネルをハイライト
function M.highlight_current_channel()
  local layout = get_layout()
  if not layout.layout.channels_buf or not vim.api.nvim_buf_is_valid(layout.layout.channels_buf) then
    return
  end

  -- 既存のハイライトをクリア
  vim.api.nvim_buf_clear_namespace(layout.layout.channels_buf, -1, 0, -1)

  -- 現在のチャンネルIDを取得
  local current_channel_id = get_state().get_current_channel()
  if not current_channel_id then
    return
  end

  -- チャンネルIDに対応する行を検索
  for line, channel_id in pairs(layout.layout.line_to_channel or {}) do
    if channel_id == current_channel_id then
      -- 行をハイライト
      vim.api.nvim_buf_add_highlight(layout.layout.channels_buf, -1, 'NeoSlackCurrentChannel', line, 0, -1)
      break
    end
  end
end

-- チャンネルを選択
function M.select_channel()
  local layout = get_layout()
  if not layout.layout.channels_buf or not vim.api.nvim_buf_is_valid(layout.layout.channels_buf) then
    return
  end

  -- カーソル位置の行を取得
  local cursor = vim.api.nvim_win_get_cursor(layout.layout.channels_win)
  local line = cursor[1] - 1 -- 0-indexedに変換

  -- セクションヘッダーの場合は折りたたみ/展開
  for _, section in ipairs(layout.layout.line_to_section or {}) do
    if section.line == line then
      M.toggle_section()
      return
    end
  end

  -- チャンネルIDを取得
  local channel_id = layout.layout.line_to_channel and layout.layout.line_to_channel[line]
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
  local layout = get_layout()
  if not layout.layout.channels_buf or not vim.api.nvim_buf_is_valid(layout.layout.channels_buf) then
    return
  end

  -- カーソル位置の行を取得
  local cursor = vim.api.nvim_win_get_cursor(layout.layout.channels_win)
  local line = cursor[1] - 1 -- 0-indexedに変換

  -- セクション情報を取得
  local section_info
  for _, section in ipairs(layout.layout.line_to_section or {}) do
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
  local layout = get_layout()
  if not layout.layout.channels_buf or not vim.api.nvim_buf_is_valid(layout.layout.channels_buf) then
    return
  end

  -- カーソル位置の行を取得
  local cursor = vim.api.nvim_win_get_cursor(layout.layout.channels_win)
  local line = cursor[1] - 1 -- 0-indexedに変換

  -- チャンネルIDを取得
  local channel_id = layout.layout.line_to_channel and layout.layout.line_to_channel[line]
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

return M