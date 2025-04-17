# neo-slack.nvim エラーハンドリングガイド

このドキュメントでは、neo-slack.nvimプラグインのエラーハンドリングシステムについて説明します。

## 概要

neo-slack.nvimでは、統一されたエラーハンドリングシステムを採用しています。このシステムは以下の目的を持っています：

1. エラーの種類を明確に定義し、一貫した方法で処理する
2. エラー情報を適切にログに記録し、ユーザーに通知する
3. エラーの詳細情報を保持し、デバッグを容易にする
4. 依存性注入パターンと組み合わせて、モジュール間の結合度を低く保つ

## エラータイプ

エラーは以下のタイプに分類されます：

- `API`: Slack APIとの通信に関連するエラー
- `NETWORK`: ネットワーク接続に関連するエラー
- `CONFIG`: 設定に関連するエラー
- `AUTH`: 認証に関連するエラー
- `STORAGE`: ストレージ（ファイル操作など）に関連するエラー
- `INTERNAL`: プラグイン内部のエラー
- `UI`: ユーザーインターフェースに関連するエラー
- `UNKNOWN`: 分類できないエラー

## エラーオブジェクト

エラーは以下のプロパティを持つオブジェクトとして表現されます：

```lua
{
  type = "api_error",                -- エラータイプ
  message = "API request failed",    -- エラーメッセージ
  details = {                        -- 追加の詳細情報
    endpoint = "channels.list",
    status = 429,
    -- その他の詳細情報
  },
  timestamp = 1650000000             -- エラー発生時のタイムスタンプ
}
```

## エラーハンドリングモジュール

`core.errors`モジュールは、エラーハンドリングのための主要な機能を提供します：

### エラーの作成

```lua
local errors = require('neo-slack.core.errors')
local error_obj = errors.create_error(
  errors.error_types.API,
  'APIリクエストに失敗しました',
  { endpoint = 'channels.list' }
)
```

### エラーの処理

```lua
-- エラーオブジェクトを処理
errors.handle_error(error_obj)

-- エラーメッセージから直接処理
errors.handle_error('APIリクエストに失敗しました', errors.error_types.API, { endpoint = 'channels.list' })
```

### 安全な関数呼び出し

```lua
local success, result_or_error = errors.safe_call(
  function() return some_risky_function() end,
  errors.error_types.INTERNAL,
  '関数の実行中にエラーが発生しました'
)

if not success then
  -- エラー処理
end
```

### Promiseのエラーハンドリング

```lua
local promise = some_promise_returning_function()
local handled_promise = errors.handle_promise(
  promise,
  errors.error_types.API,
  'APIリクエスト中にエラーが発生しました'
)
```

## モジュールでのエラーハンドリング

### APIモジュール

APIモジュールでは、HTTPリクエストのエラー、JSONパースエラー、APIエラーを適切に処理します：

```lua
-- HTTPエラー
local error_obj = errors.create_error(
  errors.error_types.NETWORK,
  'HTTPエラー: ' .. response.status,
  { endpoint = endpoint, status = response.status }
)

-- JSONパースエラー
local error_obj = errors.create_error(
  errors.error_types.API,
  'JSONパースエラー: ' .. error_message,
  { endpoint = endpoint, body = response.body:sub(1, 100) }
)

-- APIエラー
local error_obj = errors.create_error(
  errors.error_types.API,
  'APIエラー: ' .. error_message,
  { endpoint = endpoint, error_code = error_code }
)
```

### イベントバスモジュール

イベントハンドラのエラーを捕捉し、適切に処理します：

```lua
local success, err = pcall(callback, unpack(args))
if not success then
  local error_obj = errors.create_error(
    options.error_type or errors.error_types.INTERNAL,
    'イベントハンドラでエラーが発生しました: ' .. tostring(err),
    { event = event_name, error = err }
  )
  errors.handle_error(error_obj)
end
```

### 初期化モジュール

初期化プロセスの各ステップでのエラーを適切に処理します：

```lua
local error_obj = errors.create_error(
  errors.error_types.INTERNAL,
  '初期化ステップに失敗しました: ' .. step_name,
  { step = step_name, error = error_message }
)
errors.handle_error(error_obj)
```

## エラーレベル

エラータイプごとに適切なログレベルが設定されています：

- `API`: ERROR
- `NETWORK`: ERROR
- `CONFIG`: ERROR
- `AUTH`: ERROR
- `STORAGE`: ERROR
- `INTERNAL`: ERROR
- `UI`: WARN
- `UNKNOWN`: ERROR

これらのレベルは`errors.level_map`で定義されており、必要に応じて上書きできます。

## デバッグ

エラーオブジェクトには詳細情報が含まれているため、問題のデバッグが容易になります。エラーが発生した場合は、以下の情報を確認してください：

1. エラータイプ
2. エラーメッセージ
3. 詳細情報（エンドポイント、ステータスコードなど）
4. タイムスタンプ

## ベストプラクティス

1. 適切なエラータイプを使用する
2. 明確なエラーメッセージを提供する
3. デバッグに役立つ詳細情報を含める
4. エラーを適切に処理し、ユーザーに通知する
5. 可能な場合は、エラーから回復する方法を提供する