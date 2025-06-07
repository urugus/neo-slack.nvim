-- neo-slack.nvim 構文チェックテスト
-- luassertに依存しない実装

print("Checking syntax of all Lua files...")

-- ファイルシステム操作のための関数
local function read_dir(path)
  local files = {}
  local p = io.popen("find " .. path .. ' -name "*.lua"')
  if not p then
    return files
  end

  for file in p:lines() do
    table.insert(files, file)
  end
  p:close()
  return files
end

-- 全てのLuaファイルをチェック
local files = read_dir("../lua/")
local errors = {}

for _, file in ipairs(files) do
  local success, err = loadfile(file)
  if not success then
    table.insert(errors, "Syntax error in " .. file .. ": " .. (err or ""))
  end
end

-- エラーがあれば報告
if #errors > 0 then
  for _, err in ipairs(errors) do
    print(err)
  end
  error("Syntax errors found in " .. #errors .. " files")
else
  print("All files passed syntax check")
end
