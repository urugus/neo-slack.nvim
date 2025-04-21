" Vim syntax file
" Language: Neo-Slack.nvim Messages
" Maintainer: Neo-Slack.nvim Developer
" Latest Revision: 2025-04-21

if exists("b:current_syntax")
  finish
endif

" メッセージヘッダー（ユーザー名とタイムスタンプ）
syntax match neoSlackMessageHeader /^[^[:blank:]].*(.*)/

" システムメッセージヘッダー（参加、退出など）
syntax match neoSlackSystemMessageHeader /^\[[^]]\+\].*(.*)/

" 親メッセージヘッダー（スレッド表示用）
syntax match neoSlackParentMessageHeader /^【親メッセージ】.*/

" メッセージ内容（インデントされた行）
syntax match neoSlackMessageContent /^  [^リス].*/

" リアクション情報
syntax match neoSlackReaction /^  リアクション:.*/

" スレッド情報
syntax match neoSlackThread /^  スレッド:.*/

" 空行
syntax match neoSlackEmptyLine /^$/

" メンション
syntax match neoSlackMention /@[[:alnum:]._-]\+/

" チャンネル参照
syntax match neoSlackChannel /#[[:alnum:]._-]\+/

" 絵文字
syntax match neoSlackEmoji /:[[:alnum:]_+-]\+:/

" リンク
syntax match neoSlackLink /https\?:\/\/[[:graph:]]\+/

" コードブロック
syntax region neoSlackCode start=/```/ end=/```/ contains=@NoSpell

" インラインコード
syntax region neoSlackInlineCode start=/`/ end=/`/ oneline contains=@NoSpell

" 強調
syntax match neoSlackBold /\*[^*]\+\*/
syntax match neoSlackItalic /_[^_]\+_/
syntax match neoSlackStrike /\~[^\~]\+\~/

" ハイライトの定義
highlight default link neoSlackMessageHeader Statement
highlight default link neoSlackSystemMessageHeader Special
highlight default link neoSlackParentMessageHeader Title
highlight default link neoSlackMessageContent Normal
highlight default link neoSlackReaction Constant
highlight default link neoSlackThread Comment
highlight default link neoSlackEmptyLine NonText
highlight default link neoSlackMention Identifier
highlight default link neoSlackChannel Identifier
highlight default link neoSlackEmoji Character
highlight default link neoSlackLink Underlined
highlight default link neoSlackCode String
highlight default link neoSlackInlineCode String
highlight default link neoSlackBold Bold
highlight default link neoSlackItalic Italic
highlight default link neoSlackStrike Comment

" 現在選択中のメッセージのハイライト
highlight default NeoSlackCurrentMessage term=reverse cterm=reverse gui=reverse

let b:current_syntax = "neo-slack-nvim-messages"