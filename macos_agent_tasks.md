# MiniMax Agent Clone — macOS-Only Implementation Tasks

> **Project:** MiniMaxClaude — macOS AI Agent
> **Platform:** macOS (pure native)
> **Tech Stack:** Swift | SwiftUI | XcodeGen | Claude API | MiniMax API
> **Goal:** Full MiniMax Agent functionality + Claude Code-style autonomous coding

---

## Phase 1: Project Setup & Shell

### 1.1 Repository & Toolchain

- [ ] Initialize Git repository with conventional commits
- [ ] Set up `CLAUDE.md` with project instructions
- [ ] Install XcodeGen CLI (`brew install xcodegen`)
- [ ] Create project directory structure
- [ ] Set up GitHub Actions CI for macOS builds
- [ ] Configure signing identity and capabilities
- [ ] Create App Store Connect app record

### 1.2 Xcode Project

- [ ] Create `project.yml` for XcodeGen
- [ ] Configure bundle identifier: `com.minimaxagent.app`
- [ ] Set deployment target: macOS 14.0 Sonoma
- [ ] Add app icon (1024x1024 base + all sizes)
- [ ] Configure entitlements:
  - [ ] App Sandbox: YES (with exceptions for FS access)
  - [ ] User Selected File: Read/Write
  - [ ] Network: Client
  - [ ] Automation: Apple Events
- [ ] Set up Info.plist
- [ ] Configure code signing (development + distribution)

### 1.3 Swift Package Manager

- [ ] Add dependencies (via SPM):
  - [ ] swift-llm (for API calls)
  - [ ] swift-atomics (concurrency)
  - [ ] swift-nio (networking)
  - [ ] swift-collections (data structures)

### 1.4 App Entry Point

- [ ] Create `@main` entry point
- [ ] Create `AppDelegate`
- [ ] Create `main.swift` (without @main)
- [ ] Set up menu bar
- [ ] Set up app lifecycle observers

---

## Phase 2: Core Chat Interface

### 2.1 Window Management

- [ ] Main window controller
- [ ] Window configuration (min 800x600, resizable)
- [ ] Window state persistence (position, size)
- [ ] Full-screen support
- [ ] Dark/Light mode support
- [ ] Multiple window support

### 2.2 Sidebar

- [ ] Sidebar view (240pt width)
- [ ] Toggle button (collapse/expand)
- [ ] New Chat button
- [ ] Chat history list (grouped by date)
- [ ] Search chats (⌘F)
- [ ] Delete chat (swipe or context menu)
- [ ] Rename chat (double-click)
- [ ] Pin important chats
- [ ] Chat categories/tags

### 2.3 Chat Area

- [ ] Message list view (lazy loading)
- [ ] Message bubble component:
  - [ ] User message (right-aligned)
  - [ ] AI message (left-aligned)
  - [ ] System message (centered)
  - [ ] Timestamp per message
  - [ ] Copy message button
- [ ] Markdown rendering (AttributedString)
- [ ] Code blocks with syntax highlighting
- [ ] Code block copy button
- [ ] Image rendering
- [ ] Scroll-to-bottom button
- [ ] Typing indicator

### 2.4 Input Area

- [ ] Multi-line text input (auto-grow)
- [ ] Send button (⌘Enter to send)
- [ ] Attachment button
- [ ] Voice input button
- [ ] Token count display
- [ ] Stop generating button

### 2.5 Theme System

- [ ] Light theme colors
- [ ] Dark theme colors
- [ ] System theme following
- [ ] Theme transition animations

---

## Phase 3: API Integration

### 3.1 MiniMax API Client

- [ ] API client structure
- [ ] Authentication (API key storage in Keychain)
- [ ] Chat completions endpoint
- [ ] Streaming responses (AsyncStream)
- [ ] Rate limiting
- [ ] Error handling

### 3.2 Claude API Client (Agentic Coding)

- [ ] Anthropic API client
- [ ] Tool use / function calling
- [ ] Message streaming
- [ ] Tool result handling

### 3.3 Model Management

- [ ] Model selector (MiniMax M2.7, M2.5, M2-Her)
- [ ] Default model setting
- [ ] Temperature/max tokens config
- [ ] Context window management

### 3.4 Multimodal APIs

- [ ] Image upload + vision
- [ ] Speech-to-text
- [ ] Text-to-speech (AVFoundation)
- [ ] Document parsing (PDF, DOCX)

---

## Phase 4: Agentic Coding Engine

### 4.1 Tool Definitions

- [ ] File system operations:
  - [ ] read_file(path: String) -> String
  - [ ] write_file(path: String, content: String) -> Bool
  - [ ] delete_file(path: String) -> Bool
  - [ ] list_directory(path: String) -> [FileInfo]
  - [ ] create_directory(path: String) -> Bool
- [ ] Bash execution:
  - [ ] execute_command(cmd: String, cwd: String) -> CommandResult
  - [ ] timeout handling
  - [ ] stdout/stderr capture
- [ ] Git operations:
  - [ ] git clone, status, diff, commit, push, pull

### 4.2 Sandbox & Security

- [ ] Process sandboxing
- [ ] Path traversal prevention
- [ ] Dangerous command detection
- [ ] Permission system (per-project)
- [ ] Audit logging

### 4.3 Task State Machine

- [ ] Task states (idle, planning, executing, verifying, complete, failed)
- [ ] State transitions
- [ ] Task persistence (resume on restart)
- [ ] Multi-step task support

### 4.4 Terminal Emulator

- [ ] PTY allocation
- [ ] Terminal view (SwiftUI + terminal-kit)
- [ ] ANSI color support
- [ ] Scrollback buffer
- [ ] Input/output handling

### 4.5 Project Workspace

- [ ] Open folder as project
- [ ] Recent projects list
- [ ] File tree view
- [ ] File watching (FSWatch)
- [ ] .gitignore awareness

---

## Phase 5: Floating Ball Widget

### 5.1 Floating Ball

- [ ] Floating ball view (48pt circle)
- [ ] Drag position persistence
- [ ] Edge snapping
- [ ] Multi-monitor support
- [ ] Global hotkey (⌘⇧Space)
- [ ] Pulse animation when active

### 5.2 Expanded State

- [ ] Mini chat window
- [ ] Quick ask input
- [ ] Recent queries (last 5)
- [ ] Quick actions menu

### 5.3 Quick Tools

- [ ] Screenshot capture
- [ ] Screen recording (30s)
- [ ] Clipboard access

---

## Phase 6: Preferences & Settings

### 6.1 Settings Window

- [ ] General tab (theme, launch at login)
- [ ] API tab (MiniMax + Claude keys)
- [ ] Coding tab (sandbox, allowed commands)
- [ ] Shortcuts tab
- [ ] About tab

### 6.2 Storage

- [ ] UserDefaults for preferences
- [ ] Keychain for API keys
- [ ] File-based chat storage (SQLite.swift)

---

## Phase 7: Native macOS Integration

### 7.1 Menu Bar

- [ ] Application menu
- [ ] File menu
- [ ] Edit menu
- [ ] View menu
- [ ] Window menu
- [ ] Help menu

### 7.2 System Integration

- [ ] Notifications (UserNotifications)
- [ ] Drag & drop
- [ ] Share extension
- [ ] Services menu
- [ ] Touch Bar support
- [ ] Handoff

### 7.3 Accessibility

- [ ] VoiceOver support
- [ ] Dynamic Type
- [ ] Keyboard navigation

---

## Phase 8: Performance & Reliability

### 8.1 Performance

- [ ] Lazy loading
- [ ] Efficient message rendering
- [ ] Memory management
- [ ] Startup optimization (<2s cold start)

### 8.2 Error Handling

- [ ] API error recovery
- [ ] Graceful degradation
- [ ] User-friendly error messages

### 8.3 Logging

- [ ] os.Logger usage
- [ ] Log file rotation
- [ ] Crash reporting

---

## Phase 9: Testing & Quality

### 9.1 Unit Tests

- [ ] API client tests
- [ ] State machine tests
- [ ] Tool function tests

### 9.2 UI Tests

- [ ] XCTest UI tests
- [ ] Snapshot tests

### 9.3 CI/CD

- [ ] GitHub Actions workflow
- [ ] macOS build + test
- [ ] Code signing in CI

---

## Phase 10: Distribution

### 10.1 App Store

- [ ] App Store Connect setup
- [ ] App Store metadata
- [ ] Screenshots
- [ ] Review submission

### 10.2 Notarization

- [ ] Developer ID signing
- [ ] Notarization via altool
- [ ] Stapling

### 10.3 Direct Distribution

- [ ] DMG creation
- [ ] Homebrew Cask
- [ ] Auto-update (Sparkle)

---

## Task Summary

| Phase | Name | Priority |
|-------|------|----------|
| 1 | Project Setup & Shell | P0 |
| 2 | Core Chat Interface | P0 |
| 3 | API Integration | P0 |
| 4 | Agentic Coding Engine | P0 |
| 5 | Floating Ball Widget | P1 |
| 6 | Preferences & Settings | P1 |
| 7 | Native macOS Integration | P1 |
| 8 | Performance & Reliability | P2 |
| 9 | Testing & Quality | P2 |
| 10 | Distribution | P2 |

**Total: ~280 tasks**
