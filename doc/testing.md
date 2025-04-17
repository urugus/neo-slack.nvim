# neo-slack.nvim テストガイド

このドキュメントでは、neo-slack.nvimプラグインのテスト方法について説明します。

## 概要

neo-slack.nvimでは、依存性注入パターンを活用したテスト手法を採用しています。これにより、モジュール間の依存関係をモックに置き換え、単体テストを容易に行うことができます。

## テストフレームワーク

テストには以下のライブラリを使用しています：

- **busted**: Luaのテストフレームワーク
- **luassert**: アサーションライブラリ
- **luassert.mock**: モックライブラリ

## テストの基本構造

```lua
-- テストファイルの基本構造
describe('モジュール名', function()
  local module_under_test
  local dependency_mock
  local other_module_mock

  before_each(function()
    -- 依存性注入コンテナをモック
    dependency_mock = mock(require('neo-slack.core.dependency'), true)

    -- 依存モジュールをモック
    other_module_mock = mock({
      function1 = function() end,
      function2 = function() end
    }, true)

    -- モックを依存性注入コンテナに登録
    dependency_mock.get.returns_with_args('other_module', other_module_mock)

    -- テスト対象のモジュールを再読み込み
    package.loaded['neo-slack.module_under_test'] = nil
    module_under_test = require('neo-slack.module_under_test')
  end)

  after_each(function()
    -- モックをリセット
    mock.revert(dependency_mock)
    mock.revert(other_module_mock)
  end)

  describe('function1', function()
    it('should do something', function()
      -- テスト対象の関数を実行
      module_under_test.function1()

      -- 期待される動作を検証
      assert.stub(other_module_mock.function2).was_called()
    end)
  end)
end)
```

## 依存性注入を活用したテスト

依存性注入パターンを活用することで、テスト時に実際のモジュールの代わりにモックを使用できます。

```lua
-- 依存性注入コンテナをモック
local dependency_mock = mock(require('neo-slack.core.dependency'), true)

-- 各モジュールのモックを作成
local api_mock = mock({
  setup = function() end,
  test_connection = function() end,
  get_channels = function() end
}, true)

local events_mock = mock({
  emit = function() end,
  on = function() end
}, true)

-- 依存性注入コンテナのget関数をモック
dependency_mock.get.returns_with_args('api', api_mock)
dependency_mock.get.returns_with_args('core.events', events_mock)

-- テスト対象のモジュールを再読み込み
package.loaded['neo-slack'] = nil
local neo_slack = require('neo-slack')
```

## モックの使い方

### 基本的なモックの作成

```lua
-- 空のモックオブジェクトを作成
local mock_obj = mock({}, true)

-- 関数を持つモックオブジェクトを作成
local mock_obj = mock({
  function1 = function() return 'result' end,
  function2 = function(arg1, arg2) return arg1 + arg2 end
}, true)
```

### 戻り値の設定

```lua
-- 常に同じ値を返す
mock_obj.function1.returns('fixed result')

-- 引数に応じて異なる値を返す
mock_obj.function1.returns_with_args('arg1', 'result for arg1')
mock_obj.function1.returns_with_args('arg2', 'result for arg2')
```

### 関数の挙動をカスタマイズ

```lua
-- 関数の挙動をカスタマイズ
mock_obj.function1.invokes(function(arg1, arg2)
  -- カスタム処理
  return arg1 .. arg2
end)
```

### コールバックの処理

```lua
-- コールバックを呼び出すモック
mock_obj.async_function.invokes(function(callback)
  -- 成功ケース
  callback(true, 'success result')

  -- 失敗ケース
  -- callback(false, 'error message')
end)
```

## アサーション

### 基本的なアサーション

```lua
-- 値の検証
assert.are.equal(expected, actual)
assert.are.same(expected_table, actual_table)  -- テーブルの内容を比較
assert.is_true(value)
assert.is_false(value)
assert.is_nil(value)
assert.is_not_nil(value)
```

### スタブの検証

```lua
-- 関数が呼び出されたことを検証
assert.stub(mock_obj.function1).was_called()

-- 特定の引数で呼び出されたことを検証
assert.stub(mock_obj.function1).was_called_with('arg1', 'arg2')

-- 呼び出されなかったことを検証
assert.stub(mock_obj.function1).was_not_called()

-- 呼び出し回数を検証
assert.stub(mock_obj.function1).was_called(3)  -- 3回呼び出された
```

### 任意の引数のマッチング

```lua
-- 一部の引数のみを検証
assert.stub(mock_obj.function1).was_called_with('arg1', match._)

-- 特定の条件を満たす引数を検証
assert.stub(mock_obj.function1).was_called_with(match.is_string(), match.is_number())
```

## テストケースの例

### 設定モジュールのテスト

```lua
describe('config', function()
  local config

  before_each(function()
    -- テスト対象のモジュールを再読み込み
    package.loaded['neo-slack.core.config'] = nil
    config = require('neo-slack.core.config')
  end)

  describe('setup', function()
    it('should initialize with default values', function()
      config.setup()

      assert.are.same('', config.get('token'))
      assert.are.same('general', config.get('default_channel'))
      assert.are.same(30, config.get('refresh_interval'))
      assert.is_true(config.get('notification'))
    end)

    it('should merge provided options with defaults', function()
      config.setup({
        token = 'test-token',
        default_channel = 'random'
      })

      assert.are.same('test-token', config.get('token'))
      assert.are.same('random', config.get('default_channel'))
      assert.are.same(30, config.get('refresh_interval'))
      assert.is_true(config.get('notification'))
    end)
  end)
end)
```

### APIモジュールのテスト

```lua
describe('api', function()
  local api
  local dependency_mock
  local utils_mock
  local curl_mock

  before_each(function()
    -- 依存モジュールをモック
    dependency_mock = mock(require('neo-slack.core.dependency'), true)
    utils_mock = mock({
      notify = function() end,
      Promise = {
        new = function(executor) return executor end,
        resolve = function(value) return value end,
        reject = function(err) return err end,
        then_func = function(promise, callback) return callback(promise) end,
        catch_func = function(promise, callback) return promise end
      }
    }, true)
    curl_mock = mock({
      get = function() end,
      post = function() end
    }, true)

    -- モックを依存性注入コンテナに登録
    dependency_mock.get.returns_with_args('utils', utils_mock)

    -- テスト対象のモジュールを再読み込み
    package.loaded['neo-slack.api.utils'] = nil
    api = require('neo-slack.api.utils')
  end)

  after_each(function()
    -- モックをリセット
    mock.revert(dependency_mock)
    mock.revert(utils_mock)
    mock.revert(curl_mock)
  end)

  describe('request_promise', function()
    it('should handle successful API response', function()
      -- モックの挙動を設定
      curl_mock.get.invokes(function(url, opts)
        opts.callback({
          status = 200,
          body = '{"ok":true,"data":"test"}'
        })
      end)

      -- テスト対象の関数を実行
      local resolve_spy = spy.new(function() end)
      local reject_spy = spy.new(function() end)

      api.request_promise('GET', 'test.endpoint', {}, {}, 'token', 'https://api.slack.com/')

      -- 期待される動作を検証
      assert.stub(curl_mock.get).was_called()
      assert.spy(resolve_spy).was_called()
      assert.spy(reject_spy).was_not_called()
    end)
  end)
end)
```

## テストの実行

テストは以下のコマンドで実行できます：

```bash
# 全てのテストを実行
busted test/

# 特定のテストファイルを実行
busted test/neo-slack_spec.lua

# 特定のテストグループを実行
busted test/neo-slack_spec.lua -t "config"
```

## テストカバレッジ

テストカバレッジを計測するには、LuaCovを使用します：

```bash
# カバレッジ計測付きでテストを実行
busted --coverage test/

# カバレッジレポートを生成
luacov

# カバレッジレポートを確認
cat luacov.report.out
```

## テストのベストプラクティス

1. **単一責任の原則を守る**: 各テストは一つの機能や動作のみをテストする
2. **依存性を適切にモックする**: 外部依存を持つモジュールは、依存をモックして単体テストを行う
3. **エッジケースをテストする**: 正常系だけでなく、エラーケースや境界値もテストする
4. **テストの独立性を保つ**: 各テストは他のテストに依存せず、独立して実行できるようにする
5. **テストの可読性を高める**: テスト名や説明は、何をテストしているかが明確になるようにする

## まとめ

依存性注入パターンを活用したテスト手法により、neo-slack.nvimの各モジュールは単体でテスト可能になっています。これにより、バグの早期発見や、リファクタリング時の安全性確保が可能になります。