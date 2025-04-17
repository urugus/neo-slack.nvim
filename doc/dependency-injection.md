# neo-slack.nvim 依存性注入パターンガイド

このドキュメントでは、neo-slack.nvimプラグインで採用している依存性注入パターンについて説明します。

## 概要

依存性注入パターンは、モジュール間の依存関係を明示的に管理し、結合度を低減するためのデザインパターンです。neo-slack.nvimでは、このパターンを採用して以下の問題を解決しています：

1. 循環参照の解消
2. テスト容易性の向上
3. コードの保守性向上
4. 拡張性の向上

## 依存性注入コンテナ

`core/dependency.lua`モジュールは、依存性注入コンテナとして機能します。このモジュールは以下の責務を持ちます：

1. モジュールのインスタンスを登録・管理する
2. モジュールのファクトリー関数を登録・管理する
3. 依存関係を解決し、必要なモジュールを提供する

## 基本的な使い方

### モジュールの取得

```lua
-- 依存性注入コンテナを取得
local dependency = require('neo-slack.core.dependency')

-- 依存モジュールの取得用関数
local function get_utils() return dependency.get('utils') end
local function get_events() return dependency.get('core.events') end

-- 関数内で依存モジュールを使用
function my_function()
  local utils = get_utils()
  utils.notify('メッセージ', vim.log.levels.INFO)
end
```

### モジュールの登録

```lua
-- モジュールのインスタンスを直接登録
dependency.register('my_module', my_module_instance)

-- ファクトリー関数を登録（遅延ロード）
dependency.register_factory('my_module', function()
  return require('neo-slack.my_module')
end)
```

## 遅延ロード

依存性注入コンテナは、モジュールの遅延ロードをサポートしています。ファクトリー関数を登録しておくと、そのモジュールが最初に必要とされるまでロードが遅延されます。

```lua
-- 初期化時にファクトリー関数を登録
dependency.register_factory('api', function()
  return require('neo-slack.api.init')
end)

-- 実際に使用されるまでロードされない
local api = dependency.get('api') -- この時点で初めてロードされる
```

これにより、起動時間の短縮や、メモリ使用量の最適化が可能になります。

## 循環参照の解消

依存性注入パターンの主要な利点の一つは、循環参照の問題を解消できることです。

### 従来の方法（問題あり）

```lua
-- module_a.lua
local module_b = require('module_b')
-- module_b.lua
local module_a = require('module_a') -- 循環参照！
```

### 依存性注入パターン（解決策）

```lua
-- module_a.lua
local dependency = require('neo-slack.core.dependency')
local function get_module_b() return dependency.get('module_b') end

-- module_b.lua
local dependency = require('neo-slack.core.dependency')
local function get_module_a() return dependency.get('module_a') end

-- 初期化
dependency.register_factory('module_a', function() return require('neo-slack.module_a') end)
dependency.register_factory('module_b', function() return require('neo-slack.module_b') end)
```

この方法では、モジュールは直接互いを参照するのではなく、依存性注入コンテナを介して間接的に参照します。

## テスト容易性

依存性注入パターンを使用すると、テスト時にモックオブジェクトを簡単に注入できます。

```lua
-- テストコード
local dependency = require('neo-slack.core.dependency')
local mock_module = { ... } -- モックオブジェクト

-- テスト用にモックを注入
dependency.register('module_name', mock_module)

-- テスト対象のモジュールを読み込み
local target_module = require('neo-slack.target_module')

-- テスト実行
-- target_moduleは自動的にmock_moduleを使用する
```

## モジュール構造

neo-slack.nvimでは、以下のようなモジュール構造を採用しています：

1. **コアモジュール**
   - `core/dependency.lua`: 依存性注入コンテナ
   - `core/events.lua`: イベントバス
   - `core/config.lua`: 設定管理
   - `core/initialization.lua`: 初期化プロセス
   - `core/errors.lua`: エラーハンドリング

2. **APIモジュール**
   - `api/core.lua`: API通信の基本機能
   - `api/channels.lua`: チャンネル関連のAPI
   - `api/messages.lua`: メッセージ関連のAPI
   - など

3. **機能モジュール**
   - `ui.lua`: ユーザーインターフェース
   - `notification.lua`: 通知システム
   - など

4. **ユーティリティモジュール**
   - `utils.lua`: 共通ユーティリティ関数
   - `state.lua`: 状態管理
   - `storage.lua`: ストレージ管理

## 初期化プロセス

依存性注入コンテナの初期化は、以下のように行われます：

```lua
-- 依存性コンテナを初期化
dependency.initialize()

-- 各モジュールのファクトリー関数が登録される
-- コアモジュール
dependency.register_factory('core.config', function() return require('neo-slack.core.config') end)
dependency.register_factory('core.events', function() return require('neo-slack.core.events') end)
-- ...

-- APIモジュール
dependency.register_factory('api', function() return require('neo-slack.api.init') end)
-- ...

-- 機能モジュール
dependency.register_factory('ui', function() return require('neo-slack.ui') end)
-- ...
```

## ベストプラクティス

1. **依存関係を明示的に宣言する**
   ```lua
   -- 依存モジュールの取得用関数を定義
   local function get_utils() return dependency.get('utils') end
   local function get_events() return dependency.get('core.events') end
   ```

2. **関数内で依存モジュールを取得する**
   ```lua
   function my_function()
     -- 関数内で依存モジュールを取得
     local utils = get_utils()
     utils.do_something()
   end
   ```

3. **循環参照を避ける**
   - 直接requireを使用せず、依存性注入コンテナを介してモジュールを取得する

4. **テスト時にモックを使用する**
   ```lua
   -- テスト用にモックを注入
   dependency.register('module_name', mock_module)
   ```

5. **エラーハンドリングを適切に行う**
   ```lua
   local success, module = pcall(dependency.get, 'module_name')
   if not success then
     -- エラー処理
   end
   ```

## まとめ

依存性注入パターンを採用することで、neo-slack.nvimは以下の利点を得ています：

1. **循環参照の解消**: モジュール間の直接的な依存関係を排除
2. **テスト容易性の向上**: モジュールの依存関係をモックに置き換え可能
3. **コードの保守性向上**: 依存関係の明示化と結合度の低下
4. **拡張性の向上**: 新機能の追加が容易に