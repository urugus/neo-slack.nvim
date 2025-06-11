-- 簡易テストランナー
-- Neovimの内蔵Luaで実行

local test_files = {
  'test/core/dependency_spec.lua',
  'test/core/events_spec.lua',
  'test/core/errors_spec.lua',
  'test/api/core_spec.lua',
  'test/state_spec.lua',
  'test/neo-slack_spec.lua'
}

-- テスト用のグローバル変数とモック
_G.describe = function(name, fn)
  print('\n--- ' .. name .. ' ---')
  fn()
end

_G.it = function(name, fn)
  local success, err = pcall(fn)
  if success then
    print('✓ ' .. name)
  else
    print('✗ ' .. name)
    print('  Error: ' .. tostring(err))
  end
end

_G.before_each = function(fn) fn() end
_G.after_each = function(fn) fn() end

-- アサーション
_G.assert = setmetatable({}, {
  __index = function(_, key)
    if key == 'equals' then
      return function(expected, actual)
        if expected ~= actual then
          error(string.format('Expected %s, got %s', tostring(expected), tostring(actual)))
        end
      end
    elseif key == 'is_true' then
      return function(value)
        if value ~= true then
          error(string.format('Expected true, got %s', tostring(value)))
        end
      end
    elseif key == 'is_false' then
      return function(value)
        if value ~= false then
          error(string.format('Expected false, got %s', tostring(value)))
        end
      end
    elseif key == 'is_nil' then
      return function(value)
        if value ~= nil then
          error(string.format('Expected nil, got %s', tostring(value)))
        end
      end
    elseif key == 'truthy' then
      return function(value)
        if not value then
          error(string.format('Expected truthy value, got %s', tostring(value)))
        end
      end
    elseif key == 'same' then
      return function(expected, actual)
        -- 簡易的な比較
        if type(expected) ~= type(actual) then
          error(string.format('Type mismatch: expected %s, got %s', type(expected), type(actual)))
        end
        if type(expected) == 'table' then
          for k, v in pairs(expected) do
            if actual[k] ~= v then
              error(string.format('Table mismatch at key %s: expected %s, got %s', tostring(k), tostring(v), tostring(actual[k])))
            end
          end
        elseif expected ~= actual then
          error(string.format('Expected %s, got %s', tostring(expected), tostring(actual)))
        end
      end
    elseif key == 'is_function' then
      return function(value)
        if type(value) ~= 'function' then
          error(string.format('Expected function, got %s', type(value)))
        end
      end
    elseif key == 'has_error' then
      return function(fn)
        local success = pcall(fn)
        if success then
          error('Expected error but none was thrown')
        end
      end
    elseif key == 'has_no_error' then
      return function(fn)
        local success, err = pcall(fn)
        if not success then
          error('Unexpected error: ' .. tostring(err))
        end
      end
    end
  end
})

-- mock関数
_G.mock = function(obj, deep)
  return obj
end

-- パスを追加
package.path = package.path .. ';./lua/?.lua;./lua/?/init.lua'

-- 各テストファイルを実行
for _, file in ipairs(test_files) do
  print('\n\n=== Running ' .. file .. ' ===')
  local success, err = pcall(dofile, file)
  if not success then
    print('Failed to run test file: ' .. tostring(err))
  end
end

print('\n\nTest run completed.')