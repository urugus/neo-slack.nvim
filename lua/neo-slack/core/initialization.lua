---@brief [[
--- neo-slack.nvim 初期化管理モジュール
--- プラグインの初期化プロセスを管理します
--- 改良版：依存性注入パターンを活用
---@brief ]]

-- 依存性注入コンテナ
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_events() return dependency.get('core.events') end
local function get_utils() return dependency.get('utils') end
local function get_config() return dependency.get('core.config') end
local function get_state() return dependency.get('state') end
local function get_storage() return dependency.get('storage') end
local function get_api() return dependency.get('api') end
local function get_errors() return dependency.get('core.errors') end

---@class NeoSlackInitialization
---@field status table 初期化ステータス
---@field steps table 初期化ステップ
---@field current_step number 現在のステップ
---@field total_steps number 全ステップ数
---@field is_initializing boolean 初期化中かどうか
---@field is_initialized boolean 初期化済みかどうか
---@field reconnect_timer any 再接続タイマー
local M = {}

-- 初期化ステータス
M.status = {
  core = false,
  storage = false,
  token = false,
  api = false,
  data = false,
  ui = false,
  events = false,
}

-- 初期化ステップ
M.steps = {
  { name = 'core', description = 'コアモジュールの初期化' },
  { name = 'storage', description = 'ストレージの初期化' },
  { name = 'token', description = 'トークンの取得' },
  { name = 'api', description = 'APIクライアントの初期化' },
  { name = 'data', description = 'データの読み込み' },
  { name = 'ui', description = 'UIの初期化' },
  { name = 'events', description = 'イベントハンドラの登録' },
}

-- 初期化状態
M.current_step = 0
M.total_steps = #M.steps
M.is_initializing = false
M.is_initialized = false
M.reconnect_timer = nil

-- 通知ヘルパー関数
---@param message string 通知メッセージ
---@param level number 通知レベル
---@param opts table|nil 追加オプション
local function notify(message, level, opts)
  opts = opts or {}
  opts.prefix = '初期化: '
  get_utils().notify(message, level, opts)
end

-- デバッグログ
---@param message string ログメッセージ
local function debug_log(message)
  if get_config().is_debug() then
    notify(message, vim.log.levels.DEBUG)
  end
end

-- 初期化ステップを開始
---@param step_name string ステップ名
---@return boolean 開始に成功したかどうか
local function start_step(step_name)
  for i, step in ipairs(M.steps) do
    if step.name == step_name then
      M.current_step = i
      get_events().emit('initialization:step_started', step_name, i, M.total_steps)
      return true
    end
  end
  return false
end

-- 初期化ステップを完了
---@param step_name string ステップ名
---@param success boolean 成功したかどうか
---@param error_message string|nil エラーメッセージ
local function complete_step(step_name, success, error_message)
  M.status[step_name] = success
  local errors = get_errors()

  if success then
  else
    local message = string.format('[%d/%d] %s に失敗しました', M.current_step, M.total_steps, M.steps[M.current_step].description)
    if error_message then
      message = message .. ': ' .. error_message
    end

    -- エラーオブジェクトを作成して処理
    local error_obj = errors.create_error(
      errors.error_types.INTERNAL,
      message,
      {
        step = step_name,
        step_number = M.current_step,
        total_steps = M.total_steps,
        original_error = error_message
      }
    )

    errors.handle_error(error_obj, nil, nil, vim.log.levels.ERROR, { prefix = '初期化: ' })
  end

  get_events().emit('initialization:step_completed', step_name, success, error_message)

  -- 全てのステップが完了したかチェック
  if M.current_step == M.total_steps then
    M.is_initializing = false
    M.is_initialized = true
    get_events().emit('initialization:completed', M.status)

    -- 成功したステップ数をカウント
    local success_count = 0
    for _, status in pairs(M.status) do
      if status then
        success_count = success_count + 1
      end
    end

    local success_rate = math.floor((success_count / M.total_steps) * 100)
    notify(string.format('初期化が完了しました (%d%%)', success_rate), vim.log.levels.INFO)

    -- 自動再接続タイマーを設定
    M.setup_reconnect_timer()
  end
end

-- 非同期で次のステップを実行
---@param callback function|nil 完了時のコールバック
local function run_next_step_async(callback)
  vim.defer_fn(function()
    M.run_next_step(callback)
  end, 0)
end

-- 次のステップを実行
---@param callback function|nil 完了時のコールバック
function M.run_next_step(callback)
  if M.current_step >= M.total_steps then
    if callback then
      callback(true)
    end
    return
  end

  local next_step = M.current_step + 1
  local step = M.steps[next_step]

  if not step then
    if callback then
      callback(true)
    end
    return
  end

  start_step(step.name)

  -- ステップごとの処理
  if step.name == 'core' then
    -- コアモジュールの初期化
    get_events().emit('core:before_init', get_config().get())
    complete_step('core', true)
    run_next_step_async(callback)

  elseif step.name == 'storage' then
    -- ストレージの初期化
    local success = get_storage().init()
    complete_step('storage', success, success and nil or 'ストレージディレクトリの作成に失敗しました')
    run_next_step_async(callback)

  elseif step.name == 'token' then
    -- トークンの取得
    local token = get_config().get('token')

    if token and token ~= '' then
      complete_step('token', true)
      run_next_step_async(callback)
    else
      -- ストレージからトークンを読み込み
      local saved_token = get_storage().load_token()

      if saved_token then
        get_config().set('token', saved_token)
        complete_step('token', true)
        run_next_step_async(callback)
      else
        -- トークンの入力を求める

        -- トークン入力プロンプトを表示
        vim.ui.input({
          prompt = 'Slack APIトークンを入力してください: ',
          default = '',
          completion = 'file',
          highlight = function()
            vim.api.nvim_buf_add_highlight(0, -1, 'Question', 0, 0, -1)
          end
        }, function(input)
          if not input or input == '' then
            notify('トークンが入力されませんでした。初期化を中断します。', vim.log.levels.WARN)
            complete_step('token', false, 'トークンが入力されませんでした')
            if callback then
              callback(false)
            end
            return
          end

          -- トークンを設定
          get_config().set('token', input)

          -- トークンを保存
          if get_storage().save_token(input) then
            notify('トークンを保存しました', vim.log.levels.INFO)
          else
            notify('トークンの保存に失敗しました', vim.log.levels.ERROR)
          end

          complete_step('token', true)
          run_next_step_async(callback)
        end)
      end
    end

  elseif step.name == 'api' then
    -- APIクライアントの初期化
    local token = get_config().get('token')

    get_api().setup(token)

    -- 接続テスト
    get_api().test_connection(function(success, data)
      if success then
        notify('Slack APIに接続しました - ワークスペース: ' .. (data.team or 'Unknown'), vim.log.levels.INFO)
        complete_step('api', true)
      else
        local errors = get_errors()
        local error_message = data.error or 'Unknown error'

        -- エラーオブジェクトを作成
        local error_obj = errors.create_error(
          errors.error_types.API,
          'Slack APIへの接続に失敗しました: ' .. error_message,
          {
            step = 'api',
            error_data = data
          }
        )

        -- エラーを処理（通知はcomplete_step内で行われる）
        complete_step('api', false, error_message)
      end
      run_next_step_async(callback)
    end)

  elseif step.name == 'data' then
    -- データの読み込み
    -- スター付きチャンネルの情報を読み込み
    local starred_channels = get_storage().load_starred_channels()
    get_state().set_starred_channels(starred_channels)

    -- カスタムセクションの情報を読み込み
    local custom_sections = get_storage().load_custom_sections()
    get_state().custom_sections = custom_sections

    -- チャンネルとセクションの関連付けを読み込み
    local channel_section_map = get_storage().load_channel_section_map()
    get_state().channel_section_map = channel_section_map

    -- セクションの折りたたみ状態を初期化
    get_state().init_section_collapsed()

    complete_step('data', true)
    run_next_step_async(callback)

  elseif step.name == 'ui' then
    -- UIの初期化
    get_state().set_initialized(true)
    complete_step('ui', true)
    run_next_step_async(callback)

  elseif step.name == 'events' then
    -- イベントハンドラの登録
    -- 注意: 循環参照を避けるため、ここではイベントハンドラを登録しない
    -- イベントハンドラは init.lua の setup 関数内で明示的に登録される
    complete_step('events', true)
    run_next_step_async(callback)

  else
    -- 未知のステップ
    notify('未知の初期化ステップです: ' .. step.name, vim.log.levels.ERROR)
    complete_step(step.name, false, '未知のステップ')
    run_next_step_async(callback)
  end
end

-- 依存性を初期化
local function initialize_dependencies()
  -- 依存性コンテナを初期化
  dependency.initialize()
end

-- 初期化を開始
---@param callback function|nil 完了時のコールバック
function M.start(callback)
  -- 依存性を初期化
  initialize_dependencies()
  if M.is_initializing then
    return
  end

  if M.is_initialized then
    if callback then
      callback(true)
    end
    return
  end

  -- 初期化状態をリセット
  M.current_step = 0
  M.is_initializing = true
  M.is_initialized = false

  for step_name, _ in pairs(M.status) do
    M.status[step_name] = false
  end

  -- 初期化開始イベントを発行
  get_events().emit('initialization:started')


  -- 最初のステップを実行
  run_next_step_async(callback)
end

-- 初期化状態を取得
---@return table 初期化状態
function M.get_status()
  return {
    status = vim.deepcopy(M.status),
    current_step = M.current_step,
    total_steps = M.total_steps,
    is_initializing = M.is_initializing,
    is_initialized = M.is_initialized
  }
end

-- 自動再接続タイマーを設定
function M.setup_reconnect_timer()
  -- 既存のタイマーをクリア
  if M.reconnect_timer then
    vim.loop.timer_stop(M.reconnect_timer)
    M.reconnect_timer = nil
  end

  -- 再接続が無効な場合は何もしない
  if not get_config().get('auto_reconnect', true) then
    return
  end

  -- 再接続間隔（秒）
  local interval = get_config().get('reconnect_interval', 300) -- デフォルト5分

  -- タイマーを作成
  M.reconnect_timer = vim.loop.new_timer()

  -- 定期的に接続をチェック
  M.reconnect_timer:start(interval * 1000, interval * 1000, vim.schedule_wrap(function()
    if not M.is_initialized then
      return
    end

    get_api().test_connection(function(success, data)
      if success then
      else
        local errors = get_errors()

        -- 接続切断エラーを作成（警告レベル）
        local disconnect_error = errors.create_error(
          errors.error_types.NETWORK,
          '接続が切断されました。再接続を試みます...',
          { last_error = data.error }
        )

        errors.handle_error(disconnect_error, nil, nil, vim.log.levels.WARN)

        -- APIクライアントを再初期化
        get_api().setup(get_config().get('token'))

        -- 再接続テスト
        get_api().test_connection(function(reconnect_success, reconnect_data)
          if reconnect_success then
            notify('再接続に成功しました - ワークスペース: ' .. (reconnect_data.team or 'Unknown'), vim.log.levels.INFO)
            get_events().emit('reconnected')
          else
            -- 再接続失敗エラーを作成
            local reconnect_error = errors.create_error(
              errors.error_types.NETWORK,
              '再接続に失敗しました: ' .. (reconnect_data.error or 'Unknown error'),
              {
                original_error = reconnect_data.error,
                error_data = reconnect_data
              }
            )

            errors.handle_error(reconnect_error)
          end
        end)
      end
    end)
  end))
end

-- 自動再接続タイマーを停止
function M.stop_reconnect_timer()
  if M.reconnect_timer then
    vim.loop.timer_stop(M.reconnect_timer)
    M.reconnect_timer = nil
  end
end

return M