" Vim syntax file
" Language: Neo-Slack Messages
" Maintainer: Neo-Slack Developer
" Latest Revision: 2025-04-06

if exists("b:current_syntax")
  finish
endif

" メッセージ一覧のヘッダー
syntax match neoSlackMessagesHeader /^# .*$/

" メッセージヘッダー
syntax match neoSlackMessageHeader /^### .*$/

" リアクション
syntax match neoSlackReaction /^> :.*$/

" スレッド情報
syntax match neoSlackThread /^> スレッド.*$/

" 区切り線
syntax match neoSlackDivider /^---$/

" メンション
syntax match neoSlackMention /<@[A-Z0-9]\+>/

" チャンネル参照
syntax match neoSlackChannel /<#[A-Z0-9]\+|[^>]\+>/

" コマンド
syntax match neoSlackCommand /^\/[a-zA-Z0-9_]\+/

" コードブロック
syntax region neoSlackCode start=/```/ end=/```/ contains=@NoSpell

" インラインコード
syntax region neoSlackInlineCode start=/`/ end=/`/ oneline contains=@NoSpell

" 絵文字
syntax match neoSlackEmoji /:[a-zA-Z0-9_+-]\+:/

" リンク
syntax match neoSlackLink /<https\?:\/\/[^>]\+>/

" 強調
syntax match neoSlackBold /\*[^*]\+\*/
syntax match neoSlackItalic /_[^_]\+_/
syntax match neoSlackStrike /~[^~]\+~/

" ハイライトの定義
highlight default link neoSlackMessagesHeader Title
highlight default link neoSlackMessageHeader Statement
highlight default link neoSlackReaction Special
highlight default link neoSlackThread Comment
highlight default link neoSlackDivider NonText
highlight default link neoSlackMention Identifier
highlight default link neoSlackChannel Identifier
highlight default link neoSlackCommand Function
highlight default link neoSlackCode String
highlight default link neoSlackInlineCode String
highlight default link neoSlackEmoji Character
highlight default link neoSlackLink Underlined
highlight default link neoSlackBold Bold
highlight default link neoSlackItalic Italic
highlight default link neoSlackStrike Comment

let b:current_syntax = "neo-slack-messages"