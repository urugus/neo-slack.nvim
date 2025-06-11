describe('NeoSlackState', function()
  local state
  local dependency_mock
  local storage_mock
  local events_mock

  before_each(function()
    -- モジュールを新しくロード
    package.loaded['neo-slack.state'] = nil
    package.loaded['neo-slack.core.dependency'] = nil
    
    -- モックオブジェクトの作成
    storage_mock = {
      load_section_collapsed = function()
        return { starred = false, channels = false }
      end,
      save_section_collapsed = function() end,
      save_starred_channels = function() end,
      save_custom_sections = function() end,
      save_channel_section_map = function() end
    }
    
    events_mock = {
      emit = function() end,
      on = function() end
    }
    
    -- 依存性モジュールのモック
    dependency_mock = {
      get = function(name)
        if name == 'storage' then
          return storage_mock
        elseif name == 'core.events' then
          return events_mock
        end
      end
    }
    
    package.loaded['neo-slack.core.dependency'] = dependency_mock
    state = require('neo-slack.state')
    
    -- 状態をリセット
    state.reset()
    
    -- os関数をモック
    _G.os = {
      time = function() return 1234567890 end
    }
    
    -- math.randomをモック
    _G.math = {
      random = function(min, max) return 5000 end
    }
    
    -- table.maxnをモック
    _G.table.maxn = function(t)
      local max = 0
      for k, _ in pairs(t) do
        if type(k) == 'number' and k > max then
          max = k
        end
      end
      return max
    end
  end)

  after_each(function()
    -- グローバル変数をクリーンアップ
    _G.os = nil
    _G.math = nil
    _G.table.maxn = nil
  end)

  describe('チャンネル管理', function()
    it('現在のチャンネルを設定・取得できる', function()
      local emit_called = false
      local emit_event = nil
      local emit_args = {}
      
      events_mock.emit = function(event, ...)
        emit_called = true
        emit_event = event
        emit_args = {...}
      end
      
      state.set_current_channel('C123456', 'general')
      
      local id, name = state.get_current_channel()
      assert.equals('C123456', id)
      assert.equals('general', name)
      assert.is_true(emit_called)
      assert.equals('state:channel_changed', emit_event)
      assert.same({'C123456', 'general'}, emit_args)
    end)

    it('チャンネルを変更するとスレッド情報がリセットされる', function()
      state.set_current_thread('1234567890.123456', { text = 'Thread message' })
      state.set_current_channel('C123456', 'general')
      
      local thread_ts, thread_msg = state.get_current_thread()
      assert.is_nil(thread_ts)
      assert.is_nil(thread_msg)
    end)

    it('silentモードでイベントを発行しない', function()
      local emit_called = false
      events_mock.emit = function()
        emit_called = true
      end
      
      state.set_current_channel('C123456', 'general', true)
      
      assert.is_false(emit_called)
    end)

    it('チャンネル一覧を設定・取得できる', function()
      local channels = {
        { id = 'C1', name = 'general' },
        { id = 'C2', name = 'random' }
      }
      
      state.set_channels(channels)
      
      assert.same(channels, state.get_channels())
    end)

    it('チャンネルIDから情報を取得できる', function()
      local channels = {
        { id = 'C1', name = 'general' },
        { id = 'C2', name = 'random' }
      }
      
      state.set_channels(channels)
      
      local channel = state.get_channel_by_id('C2')
      assert.equals('C2', channel.id)
      assert.equals('random', channel.name)
    end)

    it('チャンネル名からIDを取得できる', function()
      local channels = {
        { id = 'C1', name = 'general' },
        { id = 'C2', name = 'random' }
      }
      
      state.set_channels(channels)
      
      assert.equals('C2', state.get_channel_id_by_name('random'))
      assert.is_nil(state.get_channel_id_by_name('nonexistent'))
    end)
  end)

  describe('スレッド管理', function()
    it('現在のスレッドを設定・取得できる', function()
      local thread_message = { text = 'Thread parent message' }
      
      state.set_current_thread('1234567890.123456', thread_message)
      
      local ts, msg = state.get_current_thread()
      assert.equals('1234567890.123456', ts)
      assert.same(thread_message, msg)
    end)

    it('スレッド設定時にイベントが発行される', function()
      local emit_called = false
      local emit_event = nil
      
      events_mock.emit = function(event)
        emit_called = true
        emit_event = event
      end
      
      state.set_current_thread('1234567890.123456', {})
      
      assert.is_true(emit_called)
      assert.equals('state:thread_changed', emit_event)
    end)
  end)

  describe('メッセージ管理', function()
    it('チャンネルのメッセージを設定・取得できる', function()
      local messages = {
        { ts = '1', text = 'Message 1' },
        { ts = '2', text = 'Message 2' }
      }
      
      state.set_messages('C123456', messages)
      
      assert.same(messages, state.get_messages('C123456'))
    end)

    it('存在しないチャンネルのメッセージは空配列を返す', function()
      assert.same({}, state.get_messages('C999'))
    end)

    it('スレッドメッセージを設定・取得できる', function()
      local messages = {
        { ts = '1.1', text = 'Thread message 1' },
        { ts = '1.2', text = 'Thread message 2' }
      }
      
      state.set_thread_messages('1234567890.123456', messages)
      
      assert.same(messages, state.get_thread_messages('1234567890.123456'))
    end)

    it('タイムスタンプからメッセージを取得できる', function()
      local messages = {
        { ts = '1', text = 'Message 1' },
        { ts = '2', text = 'Message 2' }
      }
      
      state.set_messages('C123456', messages)
      
      local msg = state.get_message_by_ts('C123456', '2')
      assert.equals('2', msg.ts)
      assert.equals('Message 2', msg.text)
    end)
  end)

  describe('初期化状態管理', function()
    it('初期化状態を設定・取得できる', function()
      assert.is_false(state.is_initialized())
      
      state.set_initialized(true)
      
      assert.is_true(state.is_initialized())
    end)

    it('初期化状態変更時にイベントが発行される', function()
      local emit_called = false
      local emit_event = nil
      local emit_value = nil
      
      events_mock.emit = function(event, value)
        emit_called = true
        emit_event = event
        emit_value = value
      end
      
      state.set_initialized(true)
      
      assert.is_true(emit_called)
      assert.equals('state:initialized_changed', emit_event)
      assert.is_true(emit_value)
    end)
  end)

  describe('スター付きチャンネル管理', function()
    it('チャンネルをスター付きに設定できる', function()
      state.set_channel_starred('C123456', true)
      
      assert.is_true(state.is_channel_starred('C123456'))
    end)

    it('スター付きを解除できる', function()
      state.set_channel_starred('C123456', true)
      state.set_channel_starred('C123456', false)
      
      assert.is_false(state.is_channel_starred('C123456'))
    end)

    it('スター付きチャンネルのIDリストを取得できる', function()
      state.set_channel_starred('C1', true)
      state.set_channel_starred('C2', true)
      state.set_channel_starred('C3', false)
      
      local ids = state.get_starred_channel_ids()
      table.sort(ids) -- 順序を保証
      assert.same({'C1', 'C2'}, ids)
    end)

    it('スター付き変更時にイベントが発行される', function()
      local emit_called = false
      local emit_args = {}
      
      events_mock.emit = function(event, ...)
        emit_called = true
        emit_args = {...}
      end
      
      state.set_channel_starred('C123456', true)
      
      assert.is_true(emit_called)
      assert.same({'C123456', true}, emit_args)
    end)

    it('スター付きチャンネルを保存できる', function()
      local save_called = false
      local saved_data = nil
      
      storage_mock.save_starred_channels = function(data)
        save_called = true
        saved_data = data
      end
      
      state.set_channel_starred('C1', true)
      state.save_starred_channels()
      
      assert.is_true(save_called)
      assert.same({ C1 = true }, saved_data)
    end)
  end)

  describe('セクション管理', function()
    it('セクションの折りたたみ状態を設定・取得できる', function()
      state.set_section_collapsed('starred', true)
      
      assert.is_true(state.is_section_collapsed('starred'))
      assert.is_false(state.is_section_collapsed('channels'))
    end)

    it('セクションの折りたたみ状態を初期化できる', function()
      storage_mock.load_section_collapsed = function()
        return { starred = true, channels = false }
      end
      
      state.init_section_collapsed()
      
      assert.is_true(state.is_section_collapsed('starred'))
      assert.is_false(state.is_section_collapsed('channels'))
    end)

    it('カスタムセクションを追加できる', function()
      local section_id = state.add_section('Work')
      
      assert.equals('1234567890_5000', section_id)
      assert.equals('Work', state.custom_sections[section_id].name)
    end)

    it('セクションを削除できる', function()
      local section_id = state.add_section('Work')
      state.assign_channel_to_section('C1', section_id)
      
      state.remove_section(section_id)
      
      assert.is_nil(state.custom_sections[section_id])
      assert.is_nil(state.get_channel_section('C1'))
    end)

    it('チャンネルをセクションに割り当てできる', function()
      local section_id = state.add_section('Work')
      
      state.assign_channel_to_section('C1', section_id)
      
      assert.equals(section_id, state.get_channel_section('C1'))
    end)

    it('セクションに属するチャンネルを取得できる', function()
      local section_id = state.add_section('Work')
      state.assign_channel_to_section('C1', section_id)
      state.assign_channel_to_section('C2', section_id)
      state.assign_channel_to_section('C3', 'other_section')
      
      local channels = state.get_section_channels(section_id)
      table.sort(channels)
      assert.same({'C1', 'C2'}, channels)
    end)
  end)

  describe('ユーザーキャッシュ管理', function()
    it('ユーザー情報をキャッシュに設定・取得できる', function()
      local user_data = { id = 'U123', name = 'John Doe' }
      
      state.set_user_cache('U123', user_data)
      
      assert.same(user_data, state.get_user_by_id('U123'))
    end)

    it('キャッシュにないユーザーはイベントを発行してnilを返す', function()
      local emit_called = false
      local emit_event = nil
      local emit_user_id = nil
      
      events_mock.emit = function(event, user_id)
        emit_called = true
        emit_event = event
        emit_user_id = user_id
      end
      
      local result = state.get_user_by_id('U999')
      
      assert.is_nil(result)
      assert.is_true(emit_called)
      assert.equals('api:get_user_info_by_id', emit_event)
      assert.equals('U999', emit_user_id)
    end)

    it('ユーザー情報設定時にイベントが発行される', function()
      local emit_called = false
      local emit_args = {}
      
      events_mock.emit = function(event, ...)
        emit_called = true
        emit_args = {...}
      end
      
      local user_data = { id = 'U123', name = 'John Doe' }
      state.set_user_cache('U123', user_data)
      
      assert.is_true(emit_called)
      assert.same({'U123', user_data}, emit_args)
    end)
  end)

  describe('状態のリセット', function()
    it('reset()で全ての状態が初期化される', function()
      -- 様々な状態を設定
      state.set_current_channel('C123', 'general')
      state.set_channels({ { id = 'C1', name = 'test' } })
      state.set_messages('C1', { { ts = '1', text = 'test' } })
      state.set_initialized(true)
      state.set_channel_starred('C1', true)
      
      -- リセット
      state.reset()
      
      -- 全ての状態が初期値に戻っていることを確認
      assert.is_nil(state.get_current_channel())
      assert.same({}, state.get_channels())
      assert.same({}, state.get_messages('C1'))
      assert.is_false(state.is_initialized())
      assert.is_false(state.is_channel_starred('C1'))
    end)
  end)

  describe('イベントハンドラ', function()
    it('ユーザー情報ロードイベントのハンドラが登録される', function()
      local on_called = false
      local registered_event = nil
      
      events_mock.on = function(event, handler)
        on_called = true
        registered_event = event
        -- ハンドラを実行してテスト
        if event == 'api:user_info_by_id_loaded' then
          handler('U123', { id = 'U123', name = 'Test User' })
        end
      end
      
      -- モジュールを再読み込み
      package.loaded['neo-slack.state'] = nil
      state = require('neo-slack.state')
      
      assert.is_true(on_called)
      assert.truthy(registered_event:match('api:user_info_by_id_loaded'))
    end)

    it('現在のチャンネルID要求イベントのハンドラが登録される', function()
      local on_called = false
      local registered_event = nil
      local emit_called = false
      local emit_channel_id = nil
      
      events_mock.on = function(event, handler)
        on_called = true
        registered_event = event
        -- ハンドラを実行してテスト
        if event == 'api:get_current_channel' then
          handler()
        end
      end
      
      events_mock.emit = function(event, channel_id)
        emit_called = true
        emit_channel_id = channel_id
      end
      
      -- 現在のチャンネルを設定
      state.set_current_channel('C123456', 'general', true)
      
      -- モジュールを再読み込み
      package.loaded['neo-slack.state'] = nil
      state = require('neo-slack.state')
      
      assert.is_true(on_called)
      assert.truthy(registered_event:match('api:get_current_channel'))
    end)
  end)
end)