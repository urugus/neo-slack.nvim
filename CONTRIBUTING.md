# Contributing to neo-slack.nvim

neo-slack.nvim へのコントリビューションを歓迎します！

## 開発環境のセットアップ

### 必要なツール

- Neovim >= 0.9.5
- Lua 5.1
- LuaRocks
- [Luacheck](https://github.com/mpeterv/luacheck)
- [StyLua](https://github.com/JohnnyMorganz/StyLua)
- [Busted](https://github.com/lunarmodules/busted)

### インストール

```bash
# テスト依存のインストール
luarocks install busted
luarocks install luacov
luarocks install luacheck
```

## 開発ワークフロー

### 1. ブランチを作成

```bash
git checkout -b feature/your-feature
```

### 2. コードを変更

アーキテクチャの詳細は [CLAUDE.md](CLAUDE.md) を参照してください。

### 3. テストとリントを実行

コミット前に必ず以下を実行してください：

```bash
luacheck lua/ --no-unused --no-redefined --no-unused-args --codes
stylua --check lua/
busted test/
```

### 4. Pull Request を作成

- PR テンプレートに従って記述してください
- CI が通ることを確認してください

## コーディング規約

- **フォーマット**: StyLua の設定に従う
- **Lint**: Luacheck のルールに従う
- **コメント・メッセージ**: 日本語で記述
- **依存関係**: `require` の代わりに `dependency.get()` を使用
- **エラー処理**: 構造化エラー (`core/errors.lua`) を使用
- **非同期処理**: Promise ベースの API を使用

## バグ報告

[Issue テンプレート](https://github.com/urugus/neo-slack.nvim/issues/new/choose) を使用してバグを報告してください。

## セキュリティ

セキュリティに関する問題は、公開 Issue ではなく [Security Advisory](https://github.com/urugus/neo-slack.nvim/security/advisories/new) から報告してください。
