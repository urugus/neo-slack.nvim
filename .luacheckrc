-- Luacheck configuration for neo-slack.nvim

-- Neovim globals
std = "lua51"

-- Allow vim global
globals = {
  "vim",
  "_G",
}

-- Neovim API read-only globals
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
  "vim.log",
  "vim.notify",
  "vim.schedule",
  "vim.defer_fn",
  "vim.deepcopy",
  "vim.tbl_extend",
  "vim.inspect",
  "vim.split",
  "vim.trim",
}

-- Ignore some warnings
ignore = {
  "212", -- Unused argument
  "213", -- Unused loop variable
  "311", -- Value assigned to a local variable is unused
  "312", -- Value of an argument is unused
  "411", -- Redefining a local variable
  "412", -- Redefining an argument
  "421", -- Shadowing a local variable
  "422", -- Shadowing an argument
}

-- Project specific settings
files["lua/neo-slack/**/*.lua"] = {
  -- Additional globals for plugin modules
  globals = {
    "package",
  }
}

files["test/**/*_spec.lua"] = {
  -- Test framework globals
  globals = {
    "describe",
    "it",
    "before_each",
    "after_each",
    "assert",
    "mock",
    "spy",
    "stub",
    "pending",
    "setup",
    "teardown",
    "unpack", -- Lua 5.1
    "table.unpack", -- Lua 5.2+
  },
  read_globals = {
    "os",
    "math",
    "table",
  }
}

-- Exclude vendor files
exclude_files = {
  "lua/neo-slack/vendor/**",
}

-- Max line length
max_line_length = 120

-- Max cyclomatic complexity
max_cyclomatic_complexity = 15