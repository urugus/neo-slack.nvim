describe('NeoSlackAPICore', function()
  local api_core
  local dependency_mock
  local utils_mock
  local api_utils_mock
  local events_mock

  before_each(function()
    -- モジュールを新しくロード
    package.loaded['neo-slack.api.core'] = nil
    package.loaded['neo-slack.core.dependency'] = nil
    
    -- モックオブジェクトの作成
    utils_mock = {
      Promise = {
        then_func = function(promise, then_fn)
          if promise._resolved then
            local result = then_fn(promise._value)
            return { _resolved = true, _value = result }
          elseif promise._rejected then
            return promise
          end
          return promise
        end,
        catch_func = function(promise, catch_fn)
          if promise._rejected then
            return catch_fn(promise._error)
          end
          return promise
        end,
        reject = function(error)
          return { _rejected = true, _error = error }
        end
      }
    }
    
    api_utils_mock = {
      notify = function() end,
      request_promise = function()
        return { _resolved = true, _value = {} }
      end,
      create_callback_version = function(promise_fn)
        return function(...)
          local args = {...}
          local callback = args[#args]
          table.remove(args, #args)
          
          local promise = promise_fn(unpack(args))
          if promise._resolved then
            callback(nil, promise._value)
          else
            callback(promise._error, nil)
          end
        end
      end
    }
    
    events_mock = {
      emit = function() end
    }
    
    -- 依存性モジュールのモック
    dependency_mock = {
      get = function(name)
        if name == 'utils' then
          return utils_mock
        elseif name == 'api.utils' then
          return api_utils_mock
        elseif name == 'core.events' then
          return events_mock
        end
      end
    }
    
    package.loaded['neo-slack.core.dependency'] = dependency_mock
    api_core = require('neo-slack.api.core')
    
    -- 設定をリセット
    api_core.config = {
      base_url = 'https://slack.com/api/',
      token = '',
      team_info = nil,
      user_info = nil,
      scopes = nil
    }
    
    -- vim関数をモック
    _G.vim = {
      log = {
        levels = {
          ERROR = 3,
          WARN = 2,
          INFO = 1,
          DEBUG = 0
        }
      },
      split = function(str, sep)
        local result = {}
        for match in string.gmatch(str, "[^" .. sep .. "]+") do
          table.insert(result, match)
        end
        return result
      end,
      trim = function(str)
        return str:match("^%s*(.-)%s*$")
      end
    }
  end)

  after_each(function()
    -- グローバル変数をクリーンアップ
    _G.vim = nil
  end)

  describe('setup()', function()
    it('トークンを設定できる', function()
      api_core.setup('xoxb-test-token')
      
      assert.equals('xoxb-test-token', api_core.config.token)
      assert.is_nil(api_core.config.scopes)
    end)
  end)

  describe('request_promise()', function()
    it('APIリクエストを実行できる', function()
      api_core.setup('xoxb-test-token')
      
      local request_called = false
      local captured_args = {}
      
      api_utils_mock.request_promise = function(method, endpoint, params, options, token, base_url)
        request_called = true
        captured_args = {
          method = method,
          endpoint = endpoint,
          params = params,
          options = options,
          token = token,
          base_url = base_url
        }
        return { _resolved = true, _value = { ok = true } }
      end
      
      api_core.request_promise('GET', 'test.endpoint', { param = 'value' }, { timeout = 5000 })
      
      assert.is_true(request_called)
      assert.equals('GET', captured_args.method)
      assert.equals('test.endpoint', captured_args.endpoint)
      assert.same({ param = 'value' }, captured_args.params)
      assert.same({ timeout = 5000 }, captured_args.options)
      assert.equals('xoxb-test-token', captured_args.token)
      assert.equals('https://slack.com/api/', captured_args.base_url)
    end)
  end)

  describe('request()', function()
    it('コールバック版のAPIリクエストを実行できる', function()
      api_core.setup('xoxb-test-token')
      
      local callback_called = false
      local callback_error = nil
      local callback_data = nil
      
      api_utils_mock.request_promise = function()
        return { _resolved = true, _value = { ok = true, data = 'test' } }
      end
      
      api_core.request('GET', 'test.endpoint', {}, function(err, data)
        callback_called = true
        callback_error = err
        callback_data = data
      end)
      
      assert.is_true(callback_called)
      assert.is_nil(callback_error)
      assert.same({ ok = true, data = 'test' }, callback_data)
    end)
  end)

  describe('test_connection_promise()', function()
    it('接続テストが成功した場合、チーム情報とスコープを保存する', function()
      api_core.setup('xoxb-test-token')
      
      local emit_called = false
      local emit_event = nil
      local emit_data = nil
      
      api_utils_mock.request_promise = function()
        return {
          _resolved = true,
          _value = {
            ok = true,
            team = 'Test Team',
            user = 'Test User',
            scopes = 'chat:write,channels:read'
          }
        }
      end
      
      events_mock.emit = function(event, data)
        emit_called = true
        emit_event = event
        emit_data = data
      end
      
      local result = api_core.test_connection_promise()
      
      assert.truthy(result._resolved)
      assert.equals('Test Team', api_core.config.team_info.team)
      assert.equals('chat:write,channels:read', api_core.config.scopes)
      assert.is_true(emit_called)
      assert.equals('api:connected', emit_event)
    end)

    it('接続テストが失敗した場合、エラーを処理する', function()
      api_core.setup('xoxb-test-token')
      
      local notify_called = false
      local notify_message = nil
      local notify_level = nil
      
      local emit_called = false
      local emit_event = nil
      local emit_data = nil
      
      api_utils_mock.request_promise = function()
        return {
          _rejected = true,
          _error = { error = 'invalid_auth' }
        }
      end
      
      api_utils_mock.notify = function(msg, level)
        notify_called = true
        notify_message = msg
        notify_level = level
      end
      
      events_mock.emit = function(event, data)
        emit_called = true
        emit_event = event
        emit_data = data
      end
      
      local result = api_core.test_connection_promise()
      
      assert.truthy(result._rejected)
      assert.is_true(notify_called)
      assert.truthy(notify_message:match('接続テスト失敗'))
      assert.truthy(notify_message:match('invalid_auth'))
      assert.equals(vim.log.levels.ERROR, notify_level)
      assert.is_true(emit_called)
      assert.equals('api:connection_failed', emit_event)
    end)

    it('missing_scopeエラーの場合、必要なスコープ情報を表示する', function()
      api_core.setup('xoxb-test-token')
      
      local notify_message = nil
      
      api_utils_mock.request_promise = function()
        return {
          _rejected = true,
          _error = {
            error = 'missing_scope',
            context = {
              needed_scope = 'chat:write'
            }
          }
        }
      end
      
      api_utils_mock.notify = function(msg, level)
        notify_message = msg
      end
      
      api_core.test_connection_promise()
      
      assert.truthy(notify_message:match('必要なスコープ: chat:write'))
    end)
  end)

  describe('test_connection()', function()
    it('コールバック版の接続テストを実行できる', function()
      api_core.setup('xoxb-test-token')
      
      local callback_called = false
      local callback_error = nil
      local callback_data = nil
      
      api_utils_mock.request_promise = function()
        return {
          _resolved = true,
          _value = { ok = true, team = 'Test Team' }
        }
      end
      
      api_core.test_connection(function(err, data)
        callback_called = true
        callback_error = err
        callback_data = data
      end)
      
      assert.is_true(callback_called)
      assert.is_nil(callback_error)
      assert.equals('Test Team', callback_data.team)
    end)
  end)

  describe('get_team_info_promise()', function()
    it('チーム情報を取得できる', function()
      api_core.setup('xoxb-test-token')
      
      local request_endpoint = nil
      
      api_utils_mock.request_promise = function(method, endpoint, params)
        request_endpoint = endpoint
        return {
          _resolved = true,
          _value = { ok = true, team = { name = 'Test Team' } }
        }
      end
      
      local result = api_core.get_team_info_promise()
      
      assert.equals('team.info', request_endpoint)
      assert.truthy(result._resolved)
    end)
  end)

  describe('get_scopes()', function()
    it('現在のスコープを取得できる', function()
      api_core.config.scopes = 'chat:write,channels:read'
      
      assert.equals('chat:write,channels:read', api_core.get_scopes())
    end)

    it('スコープが設定されていない場合はnilを返す', function()
      assert.is_nil(api_core.get_scopes())
    end)
  end)

  describe('check_scopes()', function()
    it('必要なスコープが全てある場合はtrueを返す', function()
      api_core.config.scopes = 'chat:write,channels:read,users:read'
      
      local has_scopes, missing = api_core.check_scopes({'chat:write', 'channels:read'})
      
      assert.is_true(has_scopes)
      assert.is_nil(missing)
    end)

    it('不足しているスコープがある場合はfalseと不足リストを返す', function()
      api_core.config.scopes = 'chat:write'
      
      local has_scopes, missing = api_core.check_scopes({'chat:write', 'channels:read', 'users:read'})
      
      assert.is_false(has_scopes)
      assert.same({'channels:read', 'users:read'}, missing)
    end)

    it('スコープが設定されていない場合は全て不足として返す', function()
      local has_scopes, missing = api_core.check_scopes({'chat:write', 'channels:read'})
      
      assert.is_false(has_scopes)
      assert.same({'chat:write', 'channels:read'}, missing)
    end)

    it('スペースを含むスコープも正しく処理する', function()
      api_core.config.scopes = 'chat:write, channels:read , users:read'
      
      local has_scopes, missing = api_core.check_scopes({'chat:write', 'channels:read'})
      
      assert.is_true(has_scopes)
      assert.is_nil(missing)
    end)
  end)
end)