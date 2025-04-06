-- neo-slack ストレージモジュール
-- トークンなどの設定をローカルに保存・読み込みします

local M = {}

-- データ保存先のパス
M.storage_dir = vim.fn.stdpath('data') .. '/neo-slack'
M.token_file = M.storage_dir .. '/token'

-- ストレージディレクトリを初期化
function M.init()
  -- ディレクトリが存在しない場合は作成
  if vim.fn.isdirectory(M.storage_dir) == 0 then
    vim.fn.mkdir(M.storage_dir, 'p')
  end
end

-- トークンを保存
function M.save_token(token)
  M.init()
  
  local file = io.open(M.token_file, 'w')
  if not file then
    vim.notify('Neo-Slack: トークンの保存に失敗しました', vim.log.levels.ERROR)
    return false
  end
  
  file:write(token)
  file:close()
  
  -- ファイルのパーミッションを600に設定（ユーザーのみ読み書き可能）
  vim.loop.chmod(M.token_file, 384) -- 0600 in octal
  
  return true
end

-- トークンを読み込み
function M.load_token()
  if vim.fn.filereadable(M.token_file) == 0 then
    return nil
  end
  
  local file = io.open(M.token_file, 'r')
  if not file then
    return nil
  end
  
  local token = file:read('*all')
  file:close()
  
  -- 空文字列や空白のみの場合はnilを返す
  if not token or token:match('^%s*$') then
    return nil
  end
  
  return token
end

-- トークンを削除
function M.delete_token()
  if vim.fn.filereadable(M.token_file) == 1 then
    vim.fn.delete(M.token_file)
    return true
  end
  return false
end

return M