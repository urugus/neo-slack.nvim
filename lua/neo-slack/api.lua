---@brief [[
--- neo-slack.nvim API モジュール
--- Slack APIとの通信を処理します
--- 注意: このファイルは後方互換性のために残されています。
--- 新しいコードでは lua/neo-slack/api/init.lua を使用してください。
---@brief ]]

-- 新しいAPIモジュールを読み込む
local api = require('neo-slack.api.init')

-- 後方互換性のために、このモジュールをそのまま返す
return api