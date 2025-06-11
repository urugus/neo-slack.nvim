describe('NeoSlackErrors', function()
  local errors
  local dependency_mock
  local utils_mock

  before_each(function()
    -- モジュールを新しくロード
    package.loaded['neo-slack.core.errors'] = nil
    package.loaded['neo-slack.core.dependency'] = nil
    
    -- utilsモジュールのモック
    utils_mock = {
      notify = function() end,
      Promise = {
        catch_func = function(promise, catch_fn)
          -- テスト用の簡易実装
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
    
    -- 依存性モジュールのモック
    dependency_mock = {
      get = function(name)
        if name == 'utils' then
          return utils_mock
        end
      end,
      register = function() end
    }
    
    package.loaded['neo-slack.core.dependency'] = dependency_mock
    errors = require('neo-slack.core.errors')
    
    -- vim関数をモック
    _G.vim = {
      log = {
        levels = {
          ERROR = 3,
          WARN = 2,
          INFO = 1,
          DEBUG = 0
        }
      }
    }
    
    -- os.timeをモック
    _G.os = {
      time = function() return 1234567890 end
    }
  end)

  after_each(function()
    -- グローバル変数をクリーンアップ
    _G.vim = nil
    _G.os = nil
  end)

  describe('error_types', function()
    it('全てのエラータイプが定義されている', function()
      assert.equals('api_error', errors.error_types.API)
      assert.equals('network_error', errors.error_types.NETWORK)
      assert.equals('config_error', errors.error_types.CONFIG)
      assert.equals('auth_error', errors.error_types.AUTH)
      assert.equals('storage_error', errors.error_types.STORAGE)
      assert.equals('internal_error', errors.error_types.INTERNAL)
      assert.equals('ui_error', errors.error_types.UI)
      assert.equals('unknown_error', errors.error_types.UNKNOWN)
    end)
  end)

  describe('level_map', function()
    it('エラータイプごとに適切なログレベルが設定されている', function()
      assert.equals(vim.log.levels.ERROR, errors.level_map[errors.error_types.API])
      assert.equals(vim.log.levels.ERROR, errors.level_map[errors.error_types.NETWORK])
      assert.equals(vim.log.levels.ERROR, errors.level_map[errors.error_types.CONFIG])
      assert.equals(vim.log.levels.ERROR, errors.level_map[errors.error_types.AUTH])
      assert.equals(vim.log.levels.ERROR, errors.level_map[errors.error_types.STORAGE])
      assert.equals(vim.log.levels.ERROR, errors.level_map[errors.error_types.INTERNAL])
      assert.equals(vim.log.levels.WARN, errors.level_map[errors.error_types.UI])
      assert.equals(vim.log.levels.ERROR, errors.level_map[errors.error_types.UNKNOWN])
    end)
  end)

  describe('create_error()', function()
    it('エラーオブジェクトを作成できる', function()
      local err = errors.create_error(errors.error_types.API, 'API failed', { status = 404 })
      
      assert.equals(errors.error_types.API, err.type)
      assert.equals('API failed', err.message)
      assert.same({ status = 404 }, err.details)
      assert.equals(1234567890, err.timestamp)
    end)

    it('エラータイプが省略された場合はUNKNOWNになる', function()
      local err = errors.create_error(nil, 'Some error')
      
      assert.equals(errors.error_types.UNKNOWN, err.type)
    end)

    it('メッセージが省略された場合はデフォルトメッセージになる', function()
      local err = errors.create_error(errors.error_types.API, nil)
      
      assert.equals('Unknown error', err.message)
    end)

    it('詳細情報が省略された場合は空のテーブルになる', function()
      local err = errors.create_error(errors.error_types.API, 'API error')
      
      assert.same({}, err.details)
    end)
  end)

  describe('handle_error()', function()
    it('文字列からエラーオブジェクトを作成して処理する', function()
      local notify_called = false
      local notify_message = nil
      local notify_level = nil
      local notify_opts = nil
      
      utils_mock.notify = function(msg, level, opts)
        notify_called = true
        notify_message = msg
        notify_level = level
        notify_opts = opts
      end
      
      local result = errors.handle_error('Test error', errors.error_types.API, { code = 400 })
      
      assert.is_true(notify_called)
      assert.equals('Test error', notify_message)
      assert.equals(vim.log.levels.ERROR, notify_level)
      assert.equals('Error: ', notify_opts.prefix)
      
      assert.equals(errors.error_types.API, result.type)
      assert.equals('Test error', result.message)
      assert.same({ code = 400 }, result.details)
    end)

    it('既存のエラーオブジェクトを処理する', function()
      local error_obj = errors.create_error(errors.error_types.NETWORK, 'Network error')
      
      local notify_called = false
      utils_mock.notify = function()
        notify_called = true
      end
      
      local result = errors.handle_error(error_obj)
      
      assert.is_true(notify_called)
      assert.equals(error_obj, result)
    end)

    it('不明な形式のエラーを処理する', function()
      local notify_called = false
      local notify_message = nil
      
      utils_mock.notify = function(msg, level, opts)
        notify_called = true
        notify_message = msg
      end
      
      local result = errors.handle_error({ some = 'object' })
      
      assert.is_true(notify_called)
      assert.truthy(notify_message:match('table:'))
      assert.equals(errors.error_types.UNKNOWN, result.type)
    end)

    it('カスタムログレベルを指定できる', function()
      local notify_level = nil
      
      utils_mock.notify = function(msg, level, opts)
        notify_level = level
      end
      
      errors.handle_error('Test error', nil, nil, vim.log.levels.WARN)
      
      assert.equals(vim.log.levels.WARN, notify_level)
    end)

    it('カスタム通知オプションを指定できる', function()
      local notify_opts = nil
      
      utils_mock.notify = function(msg, level, opts)
        notify_opts = opts
      end
      
      errors.handle_error('Test error', nil, nil, nil, { prefix = 'Custom: ', title = 'Test' })
      
      assert.equals('Custom: ', notify_opts.prefix)
      assert.equals('Test', notify_opts.title)
    end)
  end)

  describe('safe_call()', function()
    it('関数が成功した場合、結果を返す', function()
      local func = function() return 'success' end
      
      local success, result = errors.safe_call(func)
      
      assert.is_true(success)
      assert.equals('success', result)
    end)

    it('関数がエラーを投げた場合、エラーオブジェクトを返す', function()
      local func = function() error('Test error') end
      
      local notify_called = false
      utils_mock.notify = function()
        notify_called = true
      end
      
      local success, result = errors.safe_call(func, errors.error_types.API, 'Failed to call API')
      
      assert.is_false(success)
      assert.equals(errors.error_types.API, result.type)
      assert.truthy(result.message:match('Failed to call API'))
      assert.truthy(result.message:match('Test error'))
      assert.is_true(notify_called)
    end)

    it('通知を無効化できる', function()
      local func = function() error('Test error') end
      
      local notify_called = false
      utils_mock.notify = function()
        notify_called = true
      end
      
      local success, result = errors.safe_call(func, nil, nil, false)
      
      assert.is_false(success)
      assert.is_false(notify_called)
    end)

    it('エラータイプが省略された場合はINTERNALになる', function()
      local func = function() error('Test error') end
      
      local success, result = errors.safe_call(func)
      
      assert.is_false(success)
      assert.equals(errors.error_types.INTERNAL, result.type)
    end)
  end)

  describe('handle_promise()', function()
    it('成功したPromiseはそのまま返される', function()
      local promise = { _rejected = false }
      
      local result = errors.handle_promise(promise)
      
      assert.equals(promise, result)
    end)

    it('失敗したPromiseのエラーを処理する', function()
      local promise = { _rejected = true, _error = 'Promise error' }
      
      local notify_called = false
      local notify_message = nil
      
      utils_mock.notify = function(msg)
        notify_called = true
        notify_message = msg
      end
      
      local result = errors.handle_promise(promise, errors.error_types.NETWORK, 'Network request failed')
      
      assert.is_true(result._rejected)
      assert.equals(errors.error_types.NETWORK, result._error.type)
      assert.truthy(result._error.message:match('Network request failed'))
      assert.truthy(result._error.message:match('Promise error'))
      assert.equals('Promise error', result._error.details.original_error)
      assert.is_true(notify_called)
    end)

    it('通知を無効化できる', function()
      local promise = { _rejected = true, _error = 'Promise error' }
      
      local notify_called = false
      utils_mock.notify = function()
        notify_called = true
      end
      
      errors.handle_promise(promise, nil, nil, false)
      
      assert.is_false(notify_called)
    end)

    it('エラータイプが省略された場合はUNKNOWNになる', function()
      local promise = { _rejected = true, _error = 'Promise error' }
      
      local result = errors.handle_promise(promise)
      
      assert.equals(errors.error_types.UNKNOWN, result._error.type)
    end)
  end)

  describe('dependency registration', function()
    it('モジュールが依存性コンテナに登録される', function()
      local registered_name = nil
      local registered_module = nil
      
      dependency_mock.register = function(name, module)
        registered_name = name
        registered_module = module
      end
      
      -- モジュールを再読み込み
      package.loaded['neo-slack.core.errors'] = nil
      local errors_new = require('neo-slack.core.errors')
      
      assert.equals('core.errors', registered_name)
      assert.equals(errors_new, registered_module)
    end)
  end)
end)