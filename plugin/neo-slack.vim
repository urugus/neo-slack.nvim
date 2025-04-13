" neo-slack.nvim - Neovim用Slackプラグイン
" Maintainer: Neo-Slack.nvim開発者
" Version: 0.1.0

if exists('g:loaded_neo_slack_nvim') || &cp || v:version < 700
  finish
endif
let g:loaded_neo_slack_nvim = 1

" コマンド定義
command! -nargs=0 SlackStatus lua require('neo-slack').status()
command! -nargs=0 SlackChannels lua require('neo-slack').list_channels()
command! -nargs=? SlackMessages lua require('neo-slack').list_messages(<f-args>)
command! -nargs=+ SlackSend lua require('neo-slack').send_message(<f-args>)
command! -nargs=+ SlackReply lua require('neo-slack').reply_message(<f-args>)
command! -nargs=+ SlackReact lua require('neo-slack').add_reaction(<f-args>)
command! -nargs=+ SlackUpload lua require('neo-slack').upload_file(<f-args>)
command! -nargs=0 SlackDeleteToken lua require('neo-slack').delete_token()
command! -nargs=? SlackSetToken lua require('neo-slack').prompt_for_token()
command! -nargs=0 SlackResetToken lua require('neo-slack').reset_token()
command! -nargs=0 SlackInitStatus lua require('neo-slack').get_initialization_status()

" デフォルト設定
let g:neo_slack_token = get(g:, 'neo_slack_token', '')
let g:neo_slack_default_channel = get(g:, 'neo_slack_default_channel', 'general')
let g:neo_slack_refresh_interval = get(g:, 'neo_slack_refresh_interval', 30)
let g:neo_slack_notification = get(g:, 'neo_slack_notification', 1)
let g:neo_slack_debug = get(g:, 'neo_slack_debug', 0)
let g:neo_slack_auto_reconnect = get(g:, 'neo_slack_auto_reconnect', 1)
let g:neo_slack_reconnect_interval = get(g:, 'neo_slack_reconnect_interval', 300)
let g:neo_slack_auto_open_default_channel = get(g:, 'neo_slack_auto_open_default_channel', 1)

" 初期化設定
let g:neo_slack_initialization = get(g:, 'neo_slack_initialization', {})
let g:neo_slack_initialization.async = get(g:neo_slack_initialization, 'async', 1)
let g:neo_slack_initialization.timeout = get(g:neo_slack_initialization, 'timeout', 30)
let g:neo_slack_initialization.retry = get(g:neo_slack_initialization, 'retry', {})
let g:neo_slack_initialization.retry.enabled = get(g:neo_slack_initialization.retry, 'enabled', 1)
let g:neo_slack_initialization.retry.max_attempts = get(g:neo_slack_initialization.retry, 'max_attempts', 3)
let g:neo_slack_initialization.retry.delay = get(g:neo_slack_initialization.retry, 'delay', 5)

" キーマッピング（ユーザーが設定していない場合のデフォルト）
if !exists('g:neo_slack_disable_default_mappings') || !g:neo_slack_disable_default_mappings
  nnoremap <silent> <leader>ss :SlackStatus<CR>
  nnoremap <silent> <leader>sc :SlackChannels<CR>
  nnoremap <silent> <leader>sm :SlackMessages<CR>
endif

" プラグインの初期化
" 自動初期化はデフォルトで無効化（循環参照エラーを避けるため）
" ユーザーは明示的に :SlackSetup コマンドを実行する必要があります

" 手動初期化用コマンド
command! -nargs=0 SlackSetup lua require('neo-slack').setup()

" 自動初期化の設定
if exists('g:neo_slack_auto_setup') && g:neo_slack_auto_setup
  augroup neo_slack_auto_setup
    autocmd!
    autocmd VimEnter * lua require('neo-slack').setup()
  augroup END
endif

" プラグイン終了時の処理
augroup neo_slack_shutdown
  autocmd!
  autocmd VimLeavePre * lua if require('neo-slack').initialization and require('neo-slack').initialization.is_initialized then require('neo-slack').shutdown() end
augroup END