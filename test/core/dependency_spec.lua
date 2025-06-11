describe('NeoSlackDependency', function()
  local dependency

  before_each(function()
    -- モジュールを新しくロード
    package.loaded['neo-slack.core.dependency'] = nil
    dependency = require('neo-slack.core.dependency')
    
    -- コンテナとファクトリーをクリア
    dependency.container = {}
    dependency.factories = {}
    
    -- vim.notifyをモック
    _G.vim = {
      notify = function() end,
      log = {
        levels = {
          ERROR = 3,
        }
      }
    }
  end)

  after_each(function()
    -- グローバル変数をクリーンアップ
    _G.vim = nil
  end)

  describe('register()', function()
    it('インスタンスを登録できる', function()
      local test_instance = { name = 'test' }
      dependency.register('test_module', test_instance)
      
      assert.equals(test_instance, dependency.container.test_module)
    end)

    it('既存のインスタンスを上書きできる', function()
      local instance1 = { name = 'instance1' }
      local instance2 = { name = 'instance2' }
      
      dependency.register('test_module', instance1)
      dependency.register('test_module', instance2)
      
      assert.equals(instance2, dependency.container.test_module)
    end)
  end)

  describe('register_factory()', function()
    it('ファクトリー関数を登録できる', function()
      local factory = function() return { name = 'factory_instance' } end
      dependency.register_factory('test_module', factory)
      
      assert.equals(factory, dependency.factories.test_module)
    end)

    it('既存のファクトリー関数を上書きできる', function()
      local factory1 = function() return { name = 'factory1' } end
      local factory2 = function() return { name = 'factory2' } end
      
      dependency.register_factory('test_module', factory1)
      dependency.register_factory('test_module', factory2)
      
      assert.equals(factory2, dependency.factories.test_module)
    end)
  end)

  describe('get()', function()
    it('登録済みのインスタンスを取得できる', function()
      local test_instance = { name = 'test' }
      dependency.register('test_module', test_instance)
      
      local result = dependency.get('test_module')
      assert.equals(test_instance, result)
    end)

    it('ファクトリー関数からインスタンスを生成して取得できる', function()
      local test_instance = { name = 'factory_created' }
      local factory = function() return test_instance end
      dependency.register_factory('test_module', factory)
      
      local result = dependency.get('test_module')
      assert.equals(test_instance, result)
      -- インスタンスがコンテナに保存されていることを確認
      assert.equals(test_instance, dependency.container.test_module)
    end)

    it('ファクトリー関数は一度だけ実行される', function()
      local call_count = 0
      local factory = function()
        call_count = call_count + 1
        return { name = 'factory_instance', count = call_count }
      end
      dependency.register_factory('test_module', factory)
      
      local result1 = dependency.get('test_module')
      local result2 = dependency.get('test_module')
      
      assert.equals(1, call_count)
      assert.equals(result1, result2)
    end)

    it('ファクトリー関数がエラーを投げた場合、エラーを処理する', function()
      local factory = function() error('Factory error') end
      dependency.register_factory('test_module', factory)
      
      local notify_called = false
      local notify_message = nil
      _G.vim.notify = function(msg, level, opts)
        notify_called = true
        notify_message = msg
      end
      
      assert.has_error(function()
        dependency.get('test_module')
      end)
      
      assert.is_true(notify_called)
      assert.truthy(notify_message:match('依存関係の初期化に失敗しました'))
    end)

    it('requireを使ってモジュールをロードできる', function()
      -- モックモジュールを作成
      local mock_module = { name = 'required_module' }
      package.loaded['neo-slack.test_module'] = mock_module
      
      local result = dependency.get('test_module')
      assert.equals(mock_module, result)
      -- インスタンスがコンテナに保存されていることを確認
      assert.equals(mock_module, dependency.container.test_module)
      
      -- クリーンアップ
      package.loaded['neo-slack.test_module'] = nil
    end)

    it('モジュールが見つからない場合、エラーを処理する', function()
      local notify_called = false
      local notify_message = nil
      _G.vim.notify = function(msg, level, opts)
        notify_called = true
        notify_message = msg
      end
      
      assert.has_error(function()
        dependency.get('non_existent_module')
      end)
      
      assert.is_true(notify_called)
      assert.truthy(notify_message:match('依存関係が見つかりません'))
    end)

    it('インスタンスが既に存在する場合、ファクトリーは実行されない', function()
      local test_instance = { name = 'existing' }
      dependency.register('test_module', test_instance)
      
      local factory_called = false
      local factory = function()
        factory_called = true
        return { name = 'factory' }
      end
      dependency.register_factory('test_module', factory)
      
      local result = dependency.get('test_module')
      assert.equals(test_instance, result)
      assert.is_false(factory_called)
    end)
  end)

  describe('initialize()', function()
    it('全てのモジュールのファクトリーを登録する', function()
      local result = dependency.initialize()
      
      assert.is_true(result)
      -- コアモジュールのファクトリーが登録されていることを確認
      assert.truthy(dependency.factories['core.config'])
      assert.truthy(dependency.factories['core.events'])
      assert.truthy(dependency.factories['core.errors'])
      assert.truthy(dependency.factories['utils'])
      assert.truthy(dependency.factories['state'])
      assert.truthy(dependency.factories['storage'])
      
      -- APIモジュールのファクトリーが登録されていることを確認
      assert.truthy(dependency.factories['api'])
      assert.truthy(dependency.factories['api.core'])
      assert.truthy(dependency.factories['api.channels'])
      assert.truthy(dependency.factories['api.messages'])
      
      -- UIモジュールのファクトリーが登録されていることを確認
      assert.truthy(dependency.factories['ui'])
      assert.truthy(dependency.factories['ui.layout'])
      assert.truthy(dependency.factories['ui.channels'])
      assert.truthy(dependency.factories['ui.messages'])
    end)

    it('モジュール登録でエラーが発生した場合、falseを返す', function()
      -- register_factoryをモックしてエラーを投げる
      local original_register_factory = dependency.register_factory
      dependency.register_factory = function(name, factory)
        if name == 'core.config' then
          error('Registration error')
        else
          return original_register_factory(name, factory)
        end
      end
      
      local notify_called = false
      _G.vim.notify = function(msg, level)
        notify_called = true
      end
      
      local result = dependency.initialize()
      
      assert.is_false(result)
      assert.is_true(notify_called)
      
      -- 元に戻す
      dependency.register_factory = original_register_factory
    end)
  end)

  describe('循環依存のテスト', function()
    it('相互に依存するモジュールを遅延ロードできる', function()
      -- モジュールAとBが相互に依存する状況をシミュレート
      local module_a = nil
      local module_b = nil
      
      -- モジュールAのファクトリー
      dependency.register_factory('module_a', function()
        return {
          name = 'A',
          get_b = function()
            return dependency.get('module_b')
          end
        }
      end)
      
      -- モジュールBのファクトリー
      dependency.register_factory('module_b', function()
        return {
          name = 'B',
          get_a = function()
            return dependency.get('module_a')
          end
        }
      end)
      
      -- モジュールAを取得
      module_a = dependency.get('module_a')
      assert.equals('A', module_a.name)
      
      -- モジュールAからモジュールBを取得
      module_b = module_a.get_b()
      assert.equals('B', module_b.name)
      
      -- モジュールBからモジュールAを取得（既にインスタンス化されている）
      local module_a_from_b = module_b.get_a()
      assert.equals(module_a, module_a_from_b)
    end)
  end)
end)