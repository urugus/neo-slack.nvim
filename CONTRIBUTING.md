# Contributing to neo-slack.nvim

Contributions to neo-slack.nvim are welcome!

## Development Setup

### Prerequisites

- Neovim >= 0.9.5
- Lua 5.1
- LuaRocks
- [Luacheck](https://github.com/mpeterv/luacheck)
- [StyLua](https://github.com/JohnnyMorganz/StyLua)
- [Busted](https://github.com/lunarmodules/busted)

### Installation

```bash
luarocks install busted
luarocks install luacov
luarocks install luacheck
```

## Development Workflow

### 1. Create a branch

```bash
git checkout -b feature/your-feature
```

### 2. Make your changes

See [CLAUDE.md](CLAUDE.md) for architecture details.

### 3. Run tests and linting

Please run the following before committing:

```bash
luacheck lua/ --no-unused --no-redefined --no-unused-args --codes
stylua --check lua/
busted test/
```

### 4. Create a Pull Request

- Follow the PR template
- Make sure CI passes

## Coding Conventions

- **Formatting**: Follow the StyLua configuration
- **Lint**: Follow Luacheck rules
- **Comments & messages**: Written in Japanese
- **Dependencies**: Use `dependency.get()` instead of `require`
- **Error handling**: Use structured errors (`core/errors.lua`)
- **Async**: Use the Promise-based API

## Bug Reports

Please use the [Issue template](https://github.com/urugus/neo-slack.nvim/issues/new/choose) to report bugs.

## Security

Please report security issues via [Security Advisory](https://github.com/urugus/neo-slack.nvim/security/advisories/new) instead of public issues.
