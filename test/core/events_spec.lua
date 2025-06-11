describe('NeoSlackEvents', function()
  local events
  local dependency_mock

  before_each(function()
    -- モジュールを新しくロード
    package.loaded['neo-slack.core.events'] = nil
    package.loaded['neo-slack.core.dependency'] = nil
    
    -- 依存性をモック
    dependency_mock = {
      get = function(name)
        if name == 'utils' then
          return {
            notify = function() end
          }
        elseif name == 'core.errors' then
          return {
            error_types = {
              INTERNAL = 'INTERNAL',
              API = 'API'
            },
            level_map = {
              INTERNAL = 3,
              API = 3
            },
            create_error = function(type, message, details)
              return {
                type = type,
                message = message,
                details = details
              }
            end,
            handle_error = function() end
          }
        end
      end
    }
    
    package.loaded['neo-slack.core.dependency'] = dependency_mock
    events = require('neo-slack.core.events')
    
    -- イベントリスナーをクリア
    events.clear()
    events.event_history = {}
    events.debug = false
    
    -- vim関数をモック
    _G.vim = {
      log = {
        levels = {
          DEBUG = 1,
          INFO = 2,
          ERROR = 3
        }
      },
      deepcopy = function(t)
        local copy = {}
        for k, v in pairs(t) do
          if type(v) == 'table' then
            copy[k] = vim.deepcopy(v)
          else
            copy[k] = v
          end
        end
        return copy
      end,
      defer_fn = function(fn, delay)
        -- テストでは即座に実行
        fn()
      end,
      inspect = function(obj)
        return tostring(obj)
      end
    }
  end)

  after_each(function()
    -- グローバル変数をクリーンアップ
    _G.vim = nil
  end)

  describe('on()', function()
    it('イベントリスナーを登録できる', function()
      local callback = function() end
      local unsubscribe = events.on('test_event', callback)
      
      assert.truthy(events.listeners.test_event)
      assert.equals(1, #events.listeners.test_event)
      assert.equals(callback, events.listeners.test_event[1].callback)
      assert.is_function(unsubscribe)
    end)

    it('同じイベントに複数のリスナーを登録できる', function()
      local callback1 = function() end
      local callback2 = function() end
      
      events.on('test_event', callback1)
      events.on('test_event', callback2)
      
      assert.equals(2, #events.listeners.test_event)
    end)

    it('名前空間付きイベントを登録できる', function()
      local callback = function() end
      events.on('test_event', callback, { namespace = 'test_ns' })
      
      assert.truthy(events.listeners['test_ns:test_event'])
      assert.truthy(events.namespaces.test_ns)
      assert.equals(1, #events.namespaces.test_ns)
      assert.equals('test_event', events.namespaces.test_ns[1])
    end)

    it('登録解除関数が正しく動作する', function()
      local callback = function() end
      local unsubscribe = events.on('test_event', callback)
      
      assert.equals(1, #events.listeners.test_event)
      
      unsubscribe()
      
      assert.equals(0, #events.listeners.test_event)
    end)
  end)

  describe('once()', function()
    it('一度だけ実行されるリスナーを登録できる', function()
      local call_count = 0
      local callback = function()
        call_count = call_count + 1
      end
      
      events.once('test_event', callback)
      
      events.emit('test_event')
      assert.equals(1, call_count)
      
      events.emit('test_event')
      assert.equals(1, call_count) -- 2回目は実行されない
    end)
  end)

  describe('emit()', function()
    it('登録されたリスナーを実行できる', function()
      local called = false
      local received_data = nil
      
      events.on('test_event', function(data)
        called = true
        received_data = data
      end)
      
      events.emit('test_event', 'test_data')
      
      assert.is_true(called)
      assert.equals('test_data', received_data)
    end)

    it('複数のリスナーを順番に実行する', function()
      local call_order = {}
      
      events.on('test_event', function()
        table.insert(call_order, 1)
      end)
      
      events.on('test_event', function()
        table.insert(call_order, 2)
      end)
      
      events.emit('test_event')
      
      assert.same({1, 2}, call_order)
    end)

    it('名前空間なしのイベントも名前空間付きリスナーで受信できる', function()
      local ns_called = false
      local no_ns_called = false
      
      events.on('test_event', function()
        no_ns_called = true
      end)
      
      events.on('test_event', function()
        ns_called = true
      end, { namespace = 'test_ns' })
      
      events.emit('test_event')
      
      assert.is_true(no_ns_called)
      assert.is_true(ns_called)
    end)

    it('エラーが発生してもクラッシュしない', function()
      local second_called = false
      
      events.on('test_event', function()
        error('Test error')
      end)
      
      events.on('test_event', function()
        second_called = true
      end)
      
      assert.has_no_error(function()
        events.emit('test_event')
      end)
      
      assert.is_true(second_called)
    end)

    it('非同期リスナーを実行できる', function()
      local called = false
      
      events.on('test_event', function()
        called = true
      end, { async = true })
      
      events.emit('test_event')
      
      assert.is_true(called) -- defer_fnがモックされているので即座に実行される
    end)

    it('イベント履歴を記録する', function()
      events.emit('test_event', 'data1', 'data2')
      
      assert.equals(1, #events.event_history)
      assert.equals('test_event', events.event_history[1].event)
      assert.same({'data1', 'data2'}, events.event_history[1].args)
      assert.truthy(events.event_history[1].timestamp)
    end)

    it('履歴の最大サイズを超えたら古い履歴を削除する', function()
      events.max_history_size = 3
      
      for i = 1, 5 do
        events.emit('event_' .. i)
      end
      
      assert.equals(3, #events.event_history)
      assert.equals('event_3', events.event_history[1].event)
      assert.equals('event_5', events.event_history[3].event)
    end)
  end)

  describe('emit_namespace()', function()
    it('名前空間内の全てのイベントを発行する', function()
      local event1_called = false
      local event2_called = false
      
      events.on('event1', function() event1_called = true end, { namespace = 'ns' })
      events.on('event2', function() event2_called = true end, { namespace = 'ns' })
      
      events.emit_namespace('ns')
      
      assert.is_true(event1_called)
      assert.is_true(event2_called)
    end)

    it('存在しない名前空間の場合は何も起こらない', function()
      assert.has_no_error(function()
        events.emit_namespace('non_existent')
      end)
    end)
  end)

  describe('clear()', function()
    it('特定のイベントのリスナーをクリアできる', function()
      events.on('event1', function() end)
      events.on('event2', function() end)
      
      events.clear('event1')
      
      assert.equals(0, #(events.listeners.event1 or {}))
      assert.equals(1, #events.listeners.event2)
    end)

    it('特定の名前空間の特定のイベントをクリアできる', function()
      events.on('event', function() end)
      events.on('event', function() end, { namespace = 'ns1' })
      events.on('event', function() end, { namespace = 'ns2' })
      
      events.clear('event', 'ns1')
      
      assert.equals(1, #events.listeners.event)
      assert.equals(0, #(events.listeners['ns1:event'] or {}))
      assert.equals(1, #events.listeners['ns2:event'])
    end)

    it('特定の名前空間の全てのイベントをクリアできる', function()
      events.on('event1', function() end, { namespace = 'ns' })
      events.on('event2', function() end, { namespace = 'ns' })
      events.on('event1', function() end) -- 名前空間なし
      
      events.clear(nil, 'ns')
      
      assert.equals(0, #(events.listeners['ns:event1'] or {}))
      assert.equals(0, #(events.listeners['ns:event2'] or {}))
      assert.equals(1, #events.listeners.event1)
      assert.equals(0, #(events.namespaces.ns or {}))
    end)

    it('全てのイベントをクリアできる', function()
      events.on('event1', function() end)
      events.on('event2', function() end, { namespace = 'ns' })
      
      events.clear()
      
      assert.same({}, events.listeners)
      assert.same({}, events.namespaces)
    end)
  end)

  describe('get_stats()', function()
    it('イベントとリスナーの統計情報を取得できる', function()
      events.on('event1', function() end)
      events.on('event1', function() end)
      events.on('event2', function() end, { namespace = 'ns' })
      
      local stats = events.get_stats()
      
      assert.equals(2, stats.events.event1)
      assert.equals(1, stats.events['ns:event2'])
      assert.equals(3, stats.total_listeners)
      assert.equals(1, stats.namespaces.ns)
    end)
  end)

  describe('get_history()', function()
    it('イベント履歴を取得できる', function()
      events.emit('event1')
      events.emit('event2', 'data')
      
      local history = events.get_history()
      
      assert.equals(2, #history)
      assert.equals('event1', history[1].event)
      assert.equals('event2', history[2].event)
      assert.same({'data'}, history[2].args)
    end)

    it('制限付きで履歴を取得できる', function()
      for i = 1, 5 do
        events.emit('event' .. i)
      end
      
      local history = events.get_history(3)
      
      assert.equals(3, #history)
      assert.equals('event3', history[1].event)
      assert.equals('event5', history[3].event)
    end)
  end)

  describe('set_debug()', function()
    it('デバッグモードを設定できる', function()
      events.set_debug(true)
      assert.is_true(events.debug)
      
      events.set_debug(false)
      assert.is_false(events.debug)
    end)
  end)

  describe('エラーハンドリング', function()
    it('同期リスナーのエラーを適切に処理する', function()
      local error_handled = false
      dependency_mock.get = function(name)
        if name == 'utils' then
          return { notify = function() end }
        elseif name == 'core.errors' then
          return {
            error_types = { INTERNAL = 'INTERNAL' },
            level_map = { INTERNAL = 3 },
            create_error = function(type, message, details)
              return { type = type, message = message, details = details }
            end,
            handle_error = function()
              error_handled = true
            end
          }
        end
      end
      
      events.on('test_event', function()
        error('Sync error')
      end)
      
      events.emit('test_event')
      
      assert.is_true(error_handled)
    end)

    it('非同期リスナーのエラーを適切に処理する', function()
      local error_handled = false
      dependency_mock.get = function(name)
        if name == 'utils' then
          return { notify = function() end }
        elseif name == 'core.errors' then
          return {
            error_types = { INTERNAL = 'INTERNAL' },
            level_map = { INTERNAL = 3 },
            create_error = function(type, message, details)
              return { type = type, message = message, details = details }
            end,
            handle_error = function()
              error_handled = true
            end
          }
        end
      end
      
      events.on('test_event', function()
        error('Async error')
      end, { async = true })
      
      events.emit('test_event')
      
      assert.is_true(error_handled)
    end)

    it('カスタムエラータイプを使用できる', function()
      local captured_error_type = nil
      dependency_mock.get = function(name)
        if name == 'utils' then
          return { notify = function() end }
        elseif name == 'core.errors' then
          return {
            error_types = { INTERNAL = 'INTERNAL', API = 'API' },
            level_map = { INTERNAL = 3, API = 3 },
            create_error = function(type, message, details)
              captured_error_type = type
              return { type = type, message = message, details = details }
            end,
            handle_error = function() end
          }
        end
      end
      
      events.on('test_event', function()
        error('API error')
      end, { error_type = 'API' })
      
      events.emit('test_event')
      
      assert.equals('API', captured_error_type)
    end)
  end)
end)