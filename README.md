# Neo-Slack.nvim

Neovimから直接Slackを操作できるプラグインです。このプラグインを使用することで、Neovimのエディタ環境を離れることなくSlackでのコミュニケーションが可能になります。

## 機能要件

- Slackワークスペースへの接続・認証
- チャンネル一覧の表示と選択
- メッセージの閲覧
- メッセージの送信
- メッセージへの返信
- リアクションの追加・削除
- DMの送受信
- メンション通知
- ファイルのアップロード
- スレッド表示
- 検索機能
- キーボードショートカットによる操作

## インストール方法

### 前提条件

- Neovim 0.5.0以上
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (オプション、検索機能向上のため)

### vim-plugを使用する場合

```vim
Plug 'nvim-lua/plenary.nvim'
Plug 'username/neo-slack.nvim'
```

### packer.nvimを使用する場合

```lua
use {
  'username/neo-slack.nvim',
  requires = { 'nvim-lua/plenary.nvim' }
}
```

### lazy.nvimを使用する場合

```lua
{
  'username/neo-slack.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    -- オプション: 明示的に初期化
    require('neo-slack').setup()
  end
}
```

### インストール後の確認

プラグインが正しくインストールされているか確認するには、Neovimで以下のコマンドを実行します：

```
:lua print(vim.inspect(package.loaded['neo-slack']))
```

`nil`が表示される場合は、プラグインがまだロードされていません。その場合は以下のコマンドを実行してください：

```
:SlackSetup
```

これにより、プラグインが初期化され、`:SlackSetToken`などのコマンドが使用可能になります。

## 設定方法

`init.vim`または`init.lua`に以下の設定を追加してください。

### トークン管理

Neo-Slackは初回起動時に自動的にSlack APIトークンの入力を求めます。入力されたトークンは安全にローカルに保存され、次回以降の起動時に自動的に読み込まれます。

トークンはNeovimの設定ファイルに直接記載する必要はありません。これにより、公開リポジトリに誤ってトークンを含めてしまうリスクを軽減できます。

### トークンの種類

Slack APIでは、2種類のトークンが使用できます:

1. **ボットトークン** (xoxb-で始まる)
   - ボットとして動作します
   - メッセージはボットの名前で送信されます
   - 特定のスコープ（権限）に制限されます

2. **ユーザートークン** (xoxp-で始まる)
   - ユーザーとして動作します
   - メッセージはユーザー自身の名前で送信されます
   - より広範なスコープ（権限）にアクセスできます

**自分自身として送信したい場合は、ユーザートークン（xoxp-）を使用してください。**

ユーザートークンの取得方法:
1. https://api.slack.com/apps にアクセス
2. アプリを選択または新規作成
3. 左メニューから「OAuth & Permissions」を選択
4. 「User Token Scopes」に必要な権限を追加:
   - channels:read, groups:read, im:read, mpim:read (チャンネル一覧の取得)
   - channels:history, groups:history, im:history, mpim:history (メッセージの取得)
   - chat:write (メッセージの送信)
   - reactions:write (リアクションの追加)
   - files:write (ファイルのアップロード)
5. 「Install to Workspace」でアプリをインストール
6. 「User OAuth Token」をコピー（xoxp-で始まるトークン）
7. `:SlackResetToken`コマンドでトークンを設定

### Vimスクリプトの場合

```vim
" 基本設定（トークンは自動的に管理されるため設定不要）
let g:neo_slack_default_channel = 'general'

" キーマッピング
nnoremap <leader>ss :SlackStatus<CR>
nnoremap <leader>sc :SlackChannels<CR>
nnoremap <leader>sm :SlackMessages<CR>
```

### Luaの場合

```lua
require('neo-slack').setup({
  -- トークンは自動的に管理されるため設定不要
  default_channel = 'general',
  refresh_interval = 30, -- メッセージ更新間隔（秒）
  notification = true,   -- 通知を有効にする
  keymaps = {
    toggle = '<leader>ss',
    channels = '<leader>sc',
    messages = '<leader>sm',
    reply = '<leader>sr',
    react = '<leader>se',
  }
})
```

### トークンの手動設定（オプション）

自動トークン管理を使用せず、従来通り設定ファイルでトークンを指定することもできます：

```vim
" Vimスクリプトの場合
let g:neo_slack_token = 'xoxp-your-slack-token'
```

```lua
-- Luaの場合
require('neo-slack').setup({
  token = 'xoxp-your-slack-token',
  -- その他の設定...
})
```

## 使用方法

### 基本コマンド

- `:SlackSetup` - プラグインを初期化（自動初期化が無効の場合や、初期化に失敗した場合に使用）
- `:SlackStatus` - Slackの接続状態を表示
- `:SlackChannels` - チャンネル一覧を表示
- `:SlackMessages [channel]` - 指定したチャンネルのメッセージを表示
- `:SlackSend [channel] [message]` - メッセージを送信
- `:SlackReply [message_ts] [reply]` - メッセージにリプライ
- `:SlackReact [message_ts] [emoji]` - メッセージにリアクションを追加
- `:SlackUpload [channel] [file_path]` - ファイルをアップロード
- `:SlackSetToken` - Slack APIトークンを設定（再設定）
- `:SlackDeleteToken` - 保存されたトークンを削除

### キーマッピング（デフォルト）

メッセージ閲覧ウィンドウ内：
- `r` - 返信モード
- `e` - リアクション追加
- `d` - リアクション削除
- `u` - ファイルアップロード
- `q` - ウィンドウを閉じる

## 開発ロードマップ

- [x] 基本設計
- [x] トークン自動管理機能
- [ ] プラグイン初期化の改善
- [ ] Slack API連携
- [ ] チャンネル表示機能
- [ ] メッセージ表示機能
- [ ] メッセージ送信機能
- [ ] リアクション機能
- [ ] ファイルアップロード機能
- [ ] 通知システム
- [ ] テスト作成
- [ ] ドキュメント整備

## 貢献方法

1. このリポジトリをフォーク
2. 機能開発用のブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add some amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. プルリクエストを作成

## ライセンス

MIT

## 謝辞

- [Neovim](https://neovim.io/)
- [Slack API](https://api.slack.com/)