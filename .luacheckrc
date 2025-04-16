-- Luacheck設定ファイル

-- Lua標準ライブラリの設定
std = "lua51"  -- Neovimは基本的にLua 5.1互換

-- グローバル変数の定義
globals = {
  "vim",
}

-- Neovim APIのグローバル変数
read_globals = {
  "vim.api",
  "vim.fn",
  "vim.cmd",
  "vim.g",
  "vim.opt",
  "vim.loop",
  "vim.lsp",
  "vim.diagnostic",
  "vim.keymap",
  "vim.json",
}

-- 無視するファイルパターン
exclude_files = {
  "lua/neo-slack/vendor/**",
}

-- 無視する警告
ignore = {
  "212", -- 未使用の引数
  "213", -- 未使用の変数
  -- "E011" は削除 - 構文エラーを検出するために無視しない
}

-- 最大行長
max_line_length = 120

-- 最大文字列長
max_string_line_length = 120

-- 最大コメント行長
max_comment_line_length = 120

-- 特定のファイルに対する設定
files = {
  -- 構文エラーを無視する設定は削除
}