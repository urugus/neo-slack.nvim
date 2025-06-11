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

### Module Development Pattern

When creating or modifying modules, follow this pattern:
```lua
-- Get dependency container
local dependency = require('neo-slack.core.dependency')

-- Define dependency getters (lazy loading)
local function get_utils() return dependency.get('utils') end
local function get_events() return dependency.get('core.events') end

-- Use dependencies within functions
function M.some_function()
  local utils = get_utils()
  utils.notify('Message', vim.log.levels.INFO)
end
```

### Event Naming Convention

- Success events: `<action>_success` (e.g., `message_sent_success`)
- Failure events: `<action>_failure`
- Namespaced events: `<namespace>:<event>` (e.g., `api:connected`)

### Plugin Commands

- `:SlackSetup` - Initialize plugin
- `:SlackStatus` - Check connection status
- `:SlackChannels` - List channels
- `:SlackMessages [channel]` - View messages in channel
- `:SlackSend [channel] [message]` - Send message
- `:SlackReply [ts] [text]` - Reply to message thread
- `:SlackReact [ts] [emoji]` - Add reaction
- `:SlackSetToken` - Configure API token

### Important Conventions

- **Japanese Documentation**: Code comments and user-facing messages are in Japanese
- **Promise/Callback Dual API**: New code uses promises (`*_promise` functions), callback versions maintained for compatibility
- **Error Types**: Use structured errors with types: API, NETWORK, CONFIG, AUTH, STORAGE, INTERNAL, UI
- **Lazy Loading**: Modules registered as factories in dependency container, loaded on first access
- **Token Security**: Tokens stored locally via storage module, never in config files