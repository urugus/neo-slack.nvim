# Neo-Slack

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
Plug 'username/neo-slack'
```

### packer.nvimを使用する場合

```lua
use {
  'username/neo-slack',
  requires = { 'nvim-lua/plenary.nvim' }
}
```

## 設定方法

`init.vim`または`init.lua`に以下の設定を追加してください。

### Vimスクリプトの場合

```vim
" 基本設定
let g:neo_slack_token = 'xoxp-your-slack-token'
let g:neo_slack_default_channel = 'general'

" キーマッピング
nnoremap <leader>ss :SlackStatus<CR>
nnoremap <leader>sc :SlackChannels<CR>
nnoremap <leader>sm :SlackMessages<CR>
```

### Luaの場合

```lua
require('neo-slack').setup({
  token = 'xoxp-your-slack-token',
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

## 使用方法

### 基本コマンド

- `:SlackStatus` - Slackの接続状態を表示
- `:SlackChannels` - チャンネル一覧を表示
- `:SlackMessages [channel]` - 指定したチャンネルのメッセージを表示
- `:SlackSend [channel] [message]` - メッセージを送信
- `:SlackReply [message_ts] [reply]` - メッセージにリプライ
- `:SlackReact [message_ts] [emoji]` - メッセージにリアクションを追加
- `:SlackUpload [channel] [file_path]` - ファイルをアップロード

### キーマッピング（デフォルト）

メッセージ閲覧ウィンドウ内：
- `r` - 返信モード
- `e` - リアクション追加
- `d` - リアクション削除
- `u` - ファイルアップロード
- `q` - ウィンドウを閉じる

## 開発ロードマップ

- [x] 基本設計
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