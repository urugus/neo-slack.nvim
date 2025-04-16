-- neo-slack.nvim プラグインのテスト

local assert = require('luassert')
local mock = require('luassert.mock')

describe('neo-slack.nvim', function()
  local neo_slack
  local api_mock
  local ui_mock
  local notification_mock

  before_each(function()
    -- モジュールのモックを作成
    api_mock = mock(require('neo-slack.api'), true)
    ui_mock = mock(require('neo-slack.ui'), true)
    notification_mock = mock(require('neo-slack.notification'), true)

    -- テスト対象のモジュールを再読み込み
    package.loaded['neo-slack'] = nil
    neo_slack = require('neo-slack')
  end)

  after_each(function()
    -- モックをリセット
    mock.revert(api_mock)
    mock.revert(ui_mock)
    mock.revert(notification_mock)
  end)

  describe('setup', function()
    it('should initialize with default config when no options provided', function()
      neo_slack.setup()

      assert.are.same('', neo_slack.config.token)
      assert.are.same('general', neo_slack.config.default_channel)
      assert.are.same(30, neo_slack.config.refresh_interval)
      assert.is_true(neo_slack.config.notification)
    end)

    it('should merge provided options with defaults', function()
      neo_slack.setup({
        token = 'test-token',
        default_channel = 'random',
      })

      assert.are.same('test-token', neo_slack.config.token)
      assert.are.same('random', neo_slack.config.default_channel)
      assert.are.same(30, neo_slack.config.refresh_interval)
      assert.is_true(neo_slack.config.notification)
    end)

    it('should initialize API client with token', function()
      neo_slack.setup({
        token = 'test-token',
      })

      assert.stub(api_mock.setup).was_called_with('test-token')
    end)

    it('should initialize notification system when enabled', function()
      neo_slack.setup({
        token = 'test-token',
        notification = true,
        refresh_interval = 60,
      })

      assert.stub(notification_mock.setup).was_called_with(60)
    end)

    it('should not initialize notification system when disabled', function()
      neo_slack.setup({
        token = 'test-token',
        notification = false,
      })

      assert.stub(notification_mock.setup).was_not_called()
    end)
  end)

  describe('status', function()
    it('should call API test_connection', function()
      neo_slack.status()

      assert.stub(api_mock.test_connection).was_called()
    end)
  end)

  describe('list_channels', function()
    it('should call API get_channels and UI show_channels on success', function()
      -- APIの成功レスポンスをシミュレート
      api_mock.get_channels.invokes(function(callback)
        callback(true, {'channel1', 'channel2'})
      end)

      neo_slack.list_channels()

      assert.stub(api_mock.get_channels).was_called()
      assert.stub(ui_mock.show_channels).was_called_with({'channel1', 'channel2'})
    end)

    it('should not call UI show_channels on API failure', function()
      -- APIの失敗レスポンスをシミュレート
      api_mock.get_channels.invokes(function(callback)
        callback(false, {error = 'API error'})
      end)

      neo_slack.list_channels()

      assert.stub(api_mock.get_channels).was_called()
      assert.stub(ui_mock.show_channels).was_not_called()
    end)
  end)

  describe('list_messages', function()
    it('should use default channel when none provided', function()
      neo_slack.config.default_channel = 'general'

      neo_slack.list_messages()

      assert.stub(api_mock.get_messages).was_called_with('general', match._)
    end)

    it('should use provided channel', function()
      neo_slack.list_messages('random')

      assert.stub(api_mock.get_messages).was_called_with('random', match._)
    end)

    it('should call UI show_messages on success', function()
      -- APIの成功レスポンスをシミュレート
      api_mock.get_messages.invokes(function(channel, callback)
        callback(true, {'message1', 'message2'})
      end)

      neo_slack.list_messages('random')

      assert.stub(ui_mock.show_messages).was_called_with('random', {'message1', 'message2'})
    end)
  end)

  describe('send_message', function()
    it('should call API send_message with channel and message', function()
      api_mock.send_message.invokes(function(channel, message, callback)
        callback(true)
      end)

      neo_slack.send_message('random', 'Hello, world!')

      assert.stub(api_mock.send_message).was_called_with('random', 'Hello, world!', match._)
    end)

    it('should use default channel when none provided', function()
      neo_slack.config.default_channel = 'general'
      api_mock.send_message.invokes(function(channel, message, callback)
        callback(true)
      end)

      neo_slack.send_message(nil, 'Hello, world!')

      assert.stub(api_mock.send_message).was_called_with('general', 'Hello, world!', match._)
    end)

    it('should concatenate multiple message arguments', function()
      api_mock.send_message.invokes(function(channel, message, callback)
        callback(true)
      end)

      neo_slack.send_message('random', 'Hello,', 'world!')

      assert.stub(api_mock.send_message).was_called_with('random', 'Hello, world!', match._)
    end)
  end)

  -- 他のメソッドのテストも同様に追加

  -- 構文チェックのテスト
  describe('syntax check', function()
    it('should have valid syntax in all lua files', function()
      local function check_file(file)
        local success, err = loadfile(file)
        assert.is_not_nil(success, "Syntax error in " .. file .. ": " .. (err or ""))
      end

      -- すべてのLuaファイルをチェック
      local handle = io.popen('find lua/ -name "*.lua"')
      local result = handle:read('*a')
      handle:close()

      for file in result:gmatch('[^\r\n]+') do
        check_file(file)
      end
    end)
  end)
end)