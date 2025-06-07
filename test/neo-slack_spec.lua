-- neo-slack.nvim プラグインのテスト

local assert = require("luassert")
local mock = require("luassert.mock")

describe("neo-slack.nvim", function()
  local neo_slack
  local dependency_mock
  local api_mock
  local ui_mock
  local events_mock
  local config_mock
  local state_mock
  local storage_mock
  local utils_mock
  local initialization_mock

  before_each(function()
    -- 依存性注入コンテナをモック
    dependency_mock = mock(require("neo-slack.core.dependency"), true)

    -- 各モジュールのモックを作成
    api_mock = mock({
      setup = function() end,
      test_connection = function() end,
      get_channels = function() end,
      get_messages = function() end,
      send_message = function() end,
      reply_message = function() end,
      get_thread_replies = function() end,
      add_reaction = function() end,
    }, true)

    ui_mock = mock({
      show = function() end,
      show_channels = function() end,
      show_messages = function() end,
      show_thread_replies = function() end,
      layout = { channels_buf = 1 },
    }, true)

    events_mock = mock({
      emit = function() end,
      on = function() end,
    }, true)

    config_mock = mock({
      setup = function() end,
      get = function()
        return "default_value"
      end,
      set = function() end,
      current = {},
    }, true)

    state_mock = mock({
      get_current_channel = function()
        return "channel_id", "channel_name"
      end,
      set_current_channel = function() end,
      set_messages = function() end,
      set_current_thread = function() end,
      set_thread_messages = function() end,
      get_current_thread = function()
        return nil
      end,
    }, true)

    storage_mock = mock({
      save_token = function()
        return true
      end,
      delete_token = function()
        return true
      end,
    }, true)

    utils_mock = mock({
      notify = function() end,
    }, true)

    initialization_mock = mock({
      start = function(callback)
        if callback then
          callback(true)
        end
      end,
      get_status = function()
        return { is_initialized = true, is_initializing = false, current_step = 8, total_steps = 8 }
      end,
    }, true)

    -- 依存性注入コンテナのget関数をモック
    dependency_mock.get.returns_with_args("api", api_mock)
    dependency_mock.get.returns_with_args("ui", ui_mock)
    dependency_mock.get.returns_with_args("core.events", events_mock)
    dependency_mock.get.returns_with_args("core.config", config_mock)
    dependency_mock.get.returns_with_args("state", state_mock)
    dependency_mock.get.returns_with_args("storage", storage_mock)
    dependency_mock.get.returns_with_args("utils", utils_mock)
    dependency_mock.get.returns_with_args("core.initialization", initialization_mock)

    -- テスト対象のモジュールを再読み込み
    package.loaded["neo-slack"] = nil
    neo_slack = require("neo-slack")
  end)

  after_each(function()
    -- モックをリセット
    mock.revert(dependency_mock)
    mock.revert(api_mock)
    mock.revert(ui_mock)
    mock.revert(events_mock)
    mock.revert(config_mock)
    mock.revert(state_mock)
    mock.revert(storage_mock)
    mock.revert(utils_mock)
    mock.revert(initialization_mock)
  end)

  describe("setup", function()
    it("should initialize with default config when no options provided", function()
      -- setup関数を呼び出す前にconfig_mockの挙動を設定
      config_mock.setup = function(opts)
        config_mock.current = {
          token = "",
          default_channel = "general",
          refresh_interval = 30,
        }
      end

      neo_slack.setup()

      -- 依存性注入を使用して設定値を検証
      assert.stub(config_mock.setup).was_called()
      assert.are.same("", neo_slack.config.token)
      assert.are.same("general", neo_slack.config.default_channel)
      assert.are.same(30, neo_slack.config.refresh_interval)
    end)

    it("should merge provided options with defaults", function()
      -- setup関数を呼び出す前にconfig_mockの挙動を設定
      config_mock.setup = function(opts)
        config_mock.current = {
          token = "test-token",
          default_channel = "random",
          refresh_interval = 30,
        }
      end

      neo_slack.setup({
        token = "test-token",
        default_channel = "random",
      })

      -- 依存性注入を使用して設定値を検証
      assert.stub(config_mock.setup).was_called()
      assert.are.same("test-token", neo_slack.config.token)
      assert.are.same("random", neo_slack.config.default_channel)
      assert.are.same(30, neo_slack.config.refresh_interval)
    end)

    it("should initialize API client with token", function()
      -- config_mockの挙動を設定
      config_mock.get.returns_with_args("token", "test-token")

      neo_slack.setup({
        token = "test-token",
      })

      -- 初期化プロセスが開始されたことを確認
      assert.stub(initialization_mock.start).was_called()
    end)

  end)

  describe("status", function()
    it("should call API test_connection and show success message", function()
      -- api_mockの挙動を設定
      api_mock.test_connection = function(callback)
        if callback then
          callback(true, { team = "test-team" })
        end
      end

      neo_slack.status()

      -- APIのtest_connection関数が呼び出されたことを確認
      assert.stub(api_mock.test_connection).was_called()

      -- 初期化状態が取得されたことを確認
      assert.stub(initialization_mock.get_status).was_called()

      -- 成功通知が表示されたことを確認
      assert.stub(utils_mock.notify).was_called()
    end)

    it("should handle API connection failure", function()
      -- api_mockの挙動を設定（失敗ケース）
      api_mock.test_connection = function(callback)
        if callback then
          callback(false, { error = "Connection error" })
        end
      end

      neo_slack.status()

      -- APIのtest_connection関数が呼び出されたことを確認
      assert.stub(api_mock.test_connection).was_called()

      -- エラー通知が表示されたことを確認
      assert.stub(utils_mock.notify).was_called()
    end)
  end)

  describe("list_channels", function()
    it("should call API get_channels and UI show_channels on success", function()
      -- ui_mockの挙動を設定
      ui_mock.layout = { channels_buf = 1 }
      vim.api = mock({
        nvim_buf_is_valid = function()
          return true
        end,
      }, true)

      -- APIの成功レスポンスをシミュレート
      api_mock.get_channels = function(callback)
        if callback then
          callback(true, { "channel1", "channel2" })
        end
      end

      neo_slack.list_channels()

      -- APIのget_channels関数が呼び出されたことを確認
      assert.stub(api_mock.get_channels).was_called()

      -- 状態にチャンネル一覧が保存されたことを確認
      assert.stub(state_mock.set_channels).was_called_with({ "channel1", "channel2" })

      -- UIにチャンネル一覧が表示されたことを確認
      assert.stub(ui_mock.show_channels).was_called_with({ "channel1", "channel2" })

      mock.revert(vim.api)
    end)

    it("should initialize UI if not already initialized", function()
      -- ui_mockの挙動を設定（UIが初期化されていない場合）
      ui_mock.layout = { channels_buf = nil }

      neo_slack.list_channels()

      -- UIが初期化されたことを確認
      assert.stub(ui_mock.show).was_called()
    end)

    it("should not call UI show_channels on API failure", function()
      -- ui_mockの挙動を設定
      ui_mock.layout = { channels_buf = 1 }
      vim.api = mock({
        nvim_buf_is_valid = function()
          return true
        end,
      }, true)

      -- APIの失敗レスポンスをシミュレート
      api_mock.get_channels = function(callback)
        if callback then
          callback(false, { error = "API error" })
        end
      end

      neo_slack.list_channels()

      -- APIのget_channels関数が呼び出されたことを確認
      assert.stub(api_mock.get_channels).was_called()

      -- UIにチャンネル一覧が表示されなかったことを確認
      assert.stub(ui_mock.show_channels).was_not_called()

      -- エラー通知が表示されたことを確認
      assert.stub(utils_mock.notify).was_called()

      mock.revert(vim.api)
    end)
  end)

  describe("list_messages", function()
    it("should use default channel when none provided", function()
      -- config_mockとstate_mockの挙動を設定
      config_mock.get.returns_with_args("default_channel", "general")
      state_mock.get_current_channel = function()
        return nil, nil
      end

      -- api_mockの挙動を設定
      api_mock.get_messages = function(channel, callback) end

      neo_slack.list_messages()

      -- APIのget_messages関数が正しいチャンネルで呼び出されたことを確認
      assert.stub(api_mock.get_messages).was_called()
      local args = api_mock.get_messages.calls[1]
      assert.are.equal("general", args[1])
    end)

    it("should use current channel when available", function()
      -- state_mockの挙動を設定
      state_mock.get_current_channel = function()
        return "current-channel", "Current Channel"
      end

      -- api_mockの挙動を設定
      api_mock.get_messages = function(channel, callback) end

      neo_slack.list_messages()

      -- APIのget_messages関数が正しいチャンネルで呼び出されたことを確認
      assert.stub(api_mock.get_messages).was_called()
      local args = api_mock.get_messages.calls[1]
      assert.are.equal("current-channel", args[1])
    end)

    it("should use provided channel", function()
      -- api_mockの挙動を設定
      api_mock.get_messages = function(channel, callback) end

      neo_slack.list_messages("random")

      -- APIのget_messages関数が正しいチャンネルで呼び出されたことを確認
      assert.stub(api_mock.get_messages).was_called()
      local args = api_mock.get_messages.calls[1]
      assert.are.equal("random", args[1])
    end)

    it("should call UI show_messages on success", function()
      -- APIの成功レスポンスをシミュレート
      api_mock.get_messages = function(channel, callback)
        if callback then
          callback(true, { "message1", "message2" })
        end
      end

      neo_slack.list_messages("random")

      -- 状態にメッセージが保存されたことを確認
      assert.stub(state_mock.set_messages).was_called_with("random", { "message1", "message2" })

      -- UIにメッセージが表示されたことを確認
      assert.stub(ui_mock.show_messages).was_called_with("random", { "message1", "message2" })
    end)

    it("should handle API failure", function()
      -- APIの失敗レスポンスをシミュレート
      api_mock.get_messages = function(channel, callback)
        if callback then
          callback(false, { error = "API error" })
        end
      end

      neo_slack.list_messages("random")

      -- エラー通知が表示されたことを確認
      assert.stub(utils_mock.notify).was_called()
    end)
  end)

  describe("send_message", function()
    it("should call API send_message with channel and message", function()
      -- api_mockの挙動を設定
      api_mock.send_message = function(channel, message, callback)
        if callback then
          callback(true)
        end
      end

      neo_slack.send_message("random", "Hello, world!")

      -- APIのsend_message関数が正しいパラメータで呼び出されたことを確認
      assert.stub(api_mock.send_message).was_called()
      local args = api_mock.send_message.calls[1]
      assert.are.equal("random", args[1])
      assert.are.equal("Hello, world!", args[2])
    end)

    it("should use current channel when none provided", function()
      -- state_mockの挙動を設定
      state_mock.get_current_channel = function()
        return "current-channel", "Current Channel"
      end

      -- api_mockの挙動を設定
      api_mock.send_message = function(channel, message, callback)
        if callback then
          callback(true)
        end
      end

      neo_slack.send_message(nil, "Hello, world!")

      -- APIのsend_message関数が正しいチャンネルで呼び出されたことを確認
      assert.stub(api_mock.send_message).was_called()
      local args = api_mock.send_message.calls[1]
      assert.are.equal("current-channel", args[1])
      assert.are.equal("Hello, world!", args[2])
    end)

    it("should use default channel when no current channel", function()
      -- state_mockとconfig_mockの挙動を設定
      state_mock.get_current_channel = function()
        return nil, nil
      end
      config_mock.get.returns_with_args("default_channel", "general")

      -- api_mockの挙動を設定
      api_mock.send_message = function(channel, message, callback)
        if callback then
          callback(true)
        end
      end

      neo_slack.send_message(nil, "Hello, world!")

      -- APIのsend_message関数が正しいチャンネルで呼び出されたことを確認
      assert.stub(api_mock.send_message).was_called()
      local args = api_mock.send_message.calls[1]
      assert.are.equal("general", args[1])
      assert.are.equal("Hello, world!", args[2])
    end)

    it("should concatenate multiple message arguments", function()
      -- api_mockの挙動を設定
      api_mock.send_message = function(channel, message, callback)
        if callback then
          callback(true)
        end
      end

      neo_slack.send_message("random", "Hello,", "world!")

      -- APIのsend_message関数が正しいパラメータで呼び出されたことを確認
      assert.stub(api_mock.send_message).was_called()
      local args = api_mock.send_message.calls[1]
      assert.are.equal("random", args[1])
      assert.are.equal("Hello, world!", args[2])
    end)

    it("should emit event and refresh messages on success", function()
      -- api_mockの挙動を設定
      api_mock.send_message = function(channel, message, callback)
        if callback then
          callback(true)
        end
      end

      neo_slack.send_message("random", "Hello, world!")

      -- イベントが発行されたことを確認
      assert.stub(events_mock.emit).was_called_with("message_sent_success", "random", "Hello, world!")
    end)

    it("should emit event on failure", function()
      -- api_mockの挙動を設定（失敗ケース）
      api_mock.send_message = function(channel, message, callback)
        if callback then
          callback(false)
        end
      end

      neo_slack.send_message("random", "Hello, world!")

      -- イベントが発行されたことを確認
      assert.stub(events_mock.emit).was_called_with("message_sent_failure", "random", "Hello, world!")
    end)
  end)

  -- 他のメソッドのテストも同様に追加
end)
