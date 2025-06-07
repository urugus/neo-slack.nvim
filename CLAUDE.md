# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Linting and Code Style
```bash
# Syntax checking with Luacheck
luacheck lua/ --no-unused --no-redefined --no-unused-args --codes

# Code formatting check with StyLua
stylua --check lua/

# Format code
stylua lua/
```

### Testing
```bash
# Run all tests with busted
busted test/

# Run specific test file
busted test/neo-slack_spec.lua

# Run tests with coverage
busted --coverage test/

# Generate coverage report
luacov

# Quick syntax check using Neovim
nvim --headless -u NONE -c "lua dofile('test/syntax_check.lua')" -c "q"
```

### Before Committing
Always run these commands before committing:
```bash
luacheck lua/
stylua --check lua/
busted test/
```

## Architecture Overview

This is a Neovim plugin for Slack integration that follows a modular, layered architecture with dependency injection.

### Core Components

1. **Dependency Injection System** (`core/dependency.lua`): Central to the architecture, enables loose coupling and testability by allowing modules to be swapped with mocks during testing.

2. **API Layer** (`api/`): Handles all Slack API interactions
   - `api/core.lua`: Base API functionality
   - `api/channels.lua`, `api/messages.lua`, etc.: Domain-specific API endpoints

3. **UI Layer** (`ui/`): Manages Neovim buffers and windows
   - `ui/layout.lua`: Window management
   - `ui/channels.lua`, `ui/messages.lua`: Specific UI components

4. **Core Services** (`core/`):
   - `core/events.lua`: Event bus for decoupled communication
   - `core/errors.lua`: Structured error handling
   - `core/initialization.lua`: Multi-step plugin initialization
   - `core/config.lua`: Configuration management

5. **State Management** (`state.lua`): Centralized application state

6. **Storage** (`storage.lua`): Persistent data (tokens, cache)

### Key Patterns

- **Dependency Injection**: All modules use `dependency.get()` instead of direct requires
- **Event-Driven**: Components communicate via events rather than direct calls
- **Promise-based Async**: API calls return promises for async operations
- **Structured Error Handling**: All errors are wrapped in structured error objects

### Testing Strategy

Tests use the dependency injection system to mock dependencies:
```lua
-- Mock the dependency container
local dependency_mock = mock(require('neo-slack.core.dependency'), true)
-- Create and inject mocks
local api_mock = mock({ test_connection = function() end }, true)
dependency_mock.get.returns_with_args('api', api_mock)
```

### Plugin Commands

- `:SlackSetup` - Initialize plugin
- `:SlackStatus` - Check connection status
- `:SlackChannels` - List channels
- `:SlackMessages` - View messages
- `:SlackSend` - Send message
- `:SlackSetToken` - Configure API token