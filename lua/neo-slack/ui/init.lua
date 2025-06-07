---@brief [[
--- neo-slack.nvim UI モジュール
--- ユーザーインターフェースを構築します
--- 分割リファクタリング版：各サブモジュールを統合します
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_api() return dependency.get('api') end
local function get_utils() return dependency.get('utils') end
local function get_state() return dependency.get('state') end
local function get_events() return dependency.get('core.events') end
local function get_layout() return dependency.get('ui.layout') end
local function get_channels() return dependency.get('ui.channels') end
local function get_messages() return dependency.get('ui.messages') end
local function get_thread() return dependency.get('ui.thread') end
local function get_keymaps() return dependency.get('ui.keymaps') end

---@class NeoSlackUI
local M = {}

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
local function notify(message, level, opts)
  opts = opts or {}
  opts.prefix = 'UI: '
  get_utils().notify(message, level, opts)
end

-- UIを表示
function M.show()
  notify('UI表示を開始します', vim.log.levels.INFO)

  -- 既存のウィンドウを閉じる
  get_layout().close()

  -- レイアウトを計算
  local layout = get_layout().calculate_layout()
  if not layout then
    notify('レイアウトの計算に失敗しました', vim.log.levels.ERROR)
    return
  end

  notify('バッファを作成します', vim.log.levels.INFO)
  -- バッファを作成
  get_layout().layout.channels_buf = get_layout().create_buffer('Neo-Slack-Channels', 'neo-slack-channels', false)
  get_layout().layout.messages_buf = get_layout().create_buffer('Neo-Slack-Messages', 'neo-slack-messages', false)

  notify('ウィンドウを作成します', vim.log.levels.INFO)
  -- ウィンドウを作成
  get_layout().layout.channels_win = get_layout().create_window(
    get_layout().layout.channels_buf,
    layout.channels_width,
    layout.height,
    2,
    2,
    'single',
    'Channels'
  )

  get_layout().layout.messages_win = get_layout().create_window(
    get_layout().layout.messages_buf,
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
      get_channels().show_channels(channels)
    else
      notify('UIからチャンネル一覧の取得に失敗しました', vim.log.levels.ERROR)
    end
  end)

  notify('キーマッピングを設定します', vim.log.levels.INFO)
  -- キーマッピングを設定
  get_keymaps().setup_keymaps()

  notify('最初のウィンドウにフォーカスします', vim.log.levels.INFO)
  -- 最初のウィンドウにフォーカス
  vim.api.nvim_set_current_win(get_layout().layout.channels_win)
end

-- UIを閉じる
function M.close()
  get_layout().close()
end

-- イベントハンドラを設定
function M.setup_event_handlers()
  -- チャンネル選択イベントのハンドラ
  get_events().on('channel_selected', function(channel_id, channel_name)
    -- 現在のチャンネルを設定
    get_state().set_current_channel(channel_id, channel_name)

    -- チャンネルをハイライト
    get_channels().highlight_current_channel()

    -- メッセージ一覧を取得
    get_api().get_messages(channel_id, function(success, messages)
      if success then
        -- メッセージを保存
        get_state().set_messages(channel_id, messages)
        -- メッセージを表示
        get_messages().show_messages(channel_id, messages)
      else
        notify('メッセージの取得に失敗しました', vim.log.levels.ERROR)
      end
    end)
  end)

  -- スレッド選択イベントのハンドラ
  get_events().on('thread_selected', function(channel_id, thread_ts)
    -- スレッド返信を取得
    get_api().get_thread_replies(channel_id, thread_ts, function(success, replies, parent_message)
      if success then
        -- スレッド返信を保存
        get_state().set_thread_messages(replies)
        -- スレッドを表示
        get_thread().show_thread(channel_id, thread_ts, replies, parent_message)
      else
        notify('スレッド返信の取得に失敗しました', vim.log.levels.ERROR)
      end
    end)
  end)
end

-- 以下は元のui.luaの関数をサブモジュールに委譲するための関数です

-- チャンネル一覧を表示
function M.show_channels(channels)
  get_channels().show_channels(channels)
end

-- チャンネルを選択
function M.select_channel()
  get_channels().select_channel()
end

-- セクションの折りたたみ/展開を切り替え
function M.toggle_section()
  get_channels().toggle_section()
end

-- チャンネルのスター付き/解除を切り替え
function M.toggle_star_channel()
  get_channels().toggle_star_channel()
end

-- チャンネル一覧を更新
function M.refresh_channels()
  get_channels().refresh_channels()
end

-- メッセージ一覧を表示
function M.show_messages(channel, messages)
  get_messages().show_messages(channel, messages)
end

-- メッセージ一覧を更新
function M.refresh_messages()
  get_messages().refresh_messages()
end

-- メッセージを送信
function M.send_message()
  get_messages().send_message()
end

-- スレッドを表示
function M.show_thread()
  get_messages().show_thread()
end

-- リアクションを追加
function M.add_reaction()
  get_messages().add_reaction()
end

-- スレッドを更新
function M.refresh_thread()
  get_thread().refresh_thread()
end

-- スレッドに返信
function M.reply_to_thread()
  get_thread().reply_to_thread()
end

-- スレッドにリアクションを追加
function M.add_reaction_to_thread()
  get_thread().add_reaction_to_thread()
end

-- スレッド表示を閉じる
function M.close_thread()
  get_thread().close_thread()
end

-- レイアウトへのアクセスを提供
M.layout = get_layout().layout

-- 依存性注入コンテナに登録
dependency.register('ui', M)
dependency.register('ui.layout', require('neo-slack.ui.layout'))
dependency.register('ui.channels', require('neo-slack.ui.channels'))
dependency.register('ui.messages', require('neo-slack.ui.messages'))
dependency.register('ui.thread', require('neo-slack.ui.thread'))
dependency.register('ui.keymaps', require('neo-slack.ui.keymaps'))

return M