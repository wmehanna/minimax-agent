# MiniMax Agent — Clone Specification

> **Source:** `agent.minimaxi.com` — Web app running on Web, Windows, Mac, iOS, Android
> **Rating:** 4.9/5 (62,374 reviews) | Price: Free
> **Company:** MiniMax (miniMax.io) — AGI company founded 2022, 200M+ users

---

## 1. Product Overview

**Tagline:** 简单指令, 无限可能 (Simple instructions, infinite possibilities)

MiniMax Agent is a **multimodal AI companion** powered by MiniMax's own large language models (M2.7, M2.5, M2-Her). It provides an all-in-one AI assistant experience combining search, vision, voice, writing, document parsing, and multi-agent collaboration via **MCP (Multi-Agent Collaboration Protocol)**.

---

## 2. Feature List

### Core Features (from Schema.org `features`)

| Feature | Description |
|---------|-------------|
| **Task Automation** | Automate complex multi-step workflows |
| **Content Creation** | Professional creative writing, marketing copy |
| **Code Generation** | Write, review, debug code |
| **Data Analysis** | Analyze data, generate insights |
| **Research Assistance** | Deep research across sources |

### Multimodal Capabilities (from product description)

| Capability | Chinese | Description |
|-----------|---------|-------------|
| **AI Search** | 精准搜索解答 | Precise search with direct answers |
| **Image Recognition** | 一目了然的图像识别 | Upload images for AI analysis |
| **Voice Dialogue** | 沉浸式语音对话 | Immersive voice interaction |
| **Creative Writing** | 专业创意写作 | Professional creative/content writing |
| **Document Parsing** | 文档闪速解析 | Upload PDFs, documents for summarization/analysis |
| **Floating Ball** | 独家悬浮球功能 | Persistent floating widget for quick access (exclusive UX feature) |
| **MCP Multi-Agent** | MCP多智能体协作 | Multiple AI agents working collaboratively |

### Use Cases

| Category | Examples |
|----------|----------|
| **AI Writing** | Articles, emails, marketing copy, social posts |
| **Study/Research** | 搜题, language learning, interview prep |
| **Office Work** | Document summarization, translation, formatting |
| **Programming** | Code generation, debugging, explanations |
| **Creative** | Story writing, content ideation |
| **Daily Use** | Chat, Q&A, general knowledge |
| **Career** | Resume optimization, interview coaching |

---

## 3. UI/UX Elements

### Platforms Supported
- Web app (`agent.minimaxi.com`)
- Windows (native app)
- macOS (native app)
- iOS (native app)
- Android (native app)
- PWA / progressive web app capabilities (`apple-mobile-web-app-capable: yes`)

### Exclusive UX Feature: Floating Ball (悬浮球)
A persistent floating action button/widget that provides quick access to the AI without navigating away from current context. Likely similar to a chat trigger or quick-action overlay.

### Visual Design (from metadata)
- **Theme:** Dark-friendly (supports `prefers-color-scheme: light/dark`)
- **OG Image:** `agent.minimaxi.com/assets/logo/favicon_v2.png`
- **App Icon:** Available at `/assets/logo/favicon_v2.png`
- **Brand Colors:** `#181E25` (dark theme base), `col-brand-00` (accent)
- **Font:** Custom font loading via Next.js

---

## 4. Architecture Signals

### Tech Stack (detected)
- **Frontend:** SwiftUI (native macOS)
- **Analytics:** Google Tag Manager (`uetq`), Microsoft Clarity
- **SEO:** Baidu, Shenma, 360, Microsoft search verifications
- **PWA:** Manifest at `/manifest.zh.json`, service worker support
- **iOS PWA:** `apple-mobile-web-app-capable` enabled

### API Endpoints (inferred)
- MiniMax Platform API at `platform.minimaxi.com`
- Streaming responses likely via SSE/WebSocket
- Auth: User account system (login required for full features)

---

## 5. Key Differentiators

1. **MCP Multi-Agent Collaboration** — Multiple specialized AI agents work together on complex tasks
2. **Floating Ball Widget** — Unique persistent quick-access UI pattern
3. **Multimodal in One Interface** — Text, image, voice, document all in one chat
4. **Powered by Proprietary Models** — M2.7/M2.5/M2-Her text models + Hailuo video + Speech audio

---

## 6. Clone Complexity Assessment

| Component | Complexity | Notes |
|-----------|------------|-------|
| Chat Interface (text) | **Low** | SwiftUI List + custom message views |
| Image Upload + Vision | **Low** | NSImage + MiniMax Vision API |
| Voice/Audio I/O | **Medium** | AVAudioEngine + AVFoundation |
| Document Upload + Parsing | **Medium** | PDFKit + LLM summary |
| Floating Ball Widget | **Medium** | NSPanel overlay |
| Agentic Coding Engine | **High** | Tool use, sandboxed execution, state machine |
| Auth/User Accounts | **Medium** | Keychain + API key management |
| Native macOS Build | **Low** | Xcode + XcodeGen, no wrapper needed |
| Streaming Responses | **Medium** | AsyncStream for SSE |
| Dark/Light Theme | **Low** | SwiftUI color schemes |

### Overall: **High** complexity (with Claude Code enhancement)
- Base MiniMax clone: **Medium-High** (per above)
- Agentic coding engine: **+High** (sandboxed execution, state machines, tool definitions)
- Recommended stack: Tauri + Rust backend + MiniMax API (text) + Claude API (agentic coding)
- Phased approach recommended (see Section 9)

---

## 6.5 Enhanced Features (NOT in Original — Adding Claude Code Capabilities)

> **Rationale:** MiniMax Agent lacks autonomous coding capabilities. This spec adds Claude Code-style agentic coding to create a truly competitive product that can autonomously operate on a codebase.

### Agentic Coding Engine

| Capability | Description | Priority |
|-----------|-------------|----------|
| **File System Operations** | Read, write, delete, rename files and directories | P0 |
| **Bash/Terminal Execution** | Run shell commands (npm, git, build tools, etc.) | P0 |
| **Git Operations** | Clone repos, branch, commit, push, pull, diff | P0 |
| **Project Workspace** | Persistent working directory with full context | P0 |
| **Multi-Turn Task Execution** | Plan → Execute → Verify → Fix cycles | P0 |
| **Tool Use / Function Calling** | LLM-driven tool invocation with retry logic | P0 |
| **Context Management** | Long-context window management, chunking large files | P1 |
| **Process Management** | Kill runaway processes, timeout handling | P1 |
| **Interactive Rebase** | Handle git conflicts, interactive rebase | P2 |

### Comparison: MiniMax Agent vs This Clone

| Feature | MiniMax Agent | This Clone (Enhanced) |
|---------|---------------|----------------------|
| Code generation | ✅ | ✅ |
| Code review/debug | ✅ | ✅ |
| File system access | ❌ | ✅ |
| Terminal execution | ❌ | ✅ |
| Git operations | ❌ | ✅ |
| Autonomous coding | ❌ | ✅ |
| Multimodal (voice/image/doc) | ✅ | ✅ |
| Floating Ball widget | ✅ | ✅ |
| MCP multi-agent | ✅ | ✅ (enhanced) |
| Cross-platform native | ✅ | ✅ |

### Architecture Implications

Adding agentic coding requires:

1. **Backend Agent Runtime** — A long-running process that executes LLM-generated code/commands
   - Sandboxed command execution
   - File system sandboxing / permission scopes
   - Process isolation and timeout enforcement

2. **State Machine** — Task lifecycle management
   - `pending` → `planning` → `executing` → `verified` → `complete`
   - Rollback on failure
   - Checkpoint/resume capability

3. **Tool Definitions** — Structured tool schemas for the LLM
   - File read/write/delete
   - Bash command execution
   - Git operations
   - Web search
   - API calls

4. **Desktop Wrapper** — Tauri is preferred over Electron
   - Native file system access
   - Better performance for sustained CLI operations
   - Smaller bundle size
   - Rust backend for tool execution

---

## 7. Visual Reference URLs

| Asset | URL |
|-------|-----|
| App Logo/OG Image | `https://agent.minimaxi.com/assets/logo/favicon_v2.png` |
| Product Banner | `https://filecdn.minimax.chat/public/887823bd-58c5-4a03-9d20-ebaa2c4edd4e.png` |
| MiniMax Logo | `https://filecdn.minimax.chat/public/969d635c-cab6-45cc-8d61-47c9fe40c81f.png` |
| Agent Product Icon | `https://filecdn.minimax.chat/public/2b22e787-ac59-4acb-b065-bf5ababe85d8.png` |

---

## 8. Competitive Context (MiniMax Product Family)

| Product | URL | Description |
|---------|-----|-------------|
| **MiniMax Agent** | `agent.minimaxi.com` | Main AI companion (this clone target) |
| **Hailuo Video** | `hailuoai.com/video` | Text-to-video generation |
| **MiniMax Audio** | `hailuoai.com/audio` | AI voice/speech synthesis |
| **MiniMax Speech** | `minimaxi.com/audio` | TTS/text-to-audio |
| **Star Field (星野)** | `xingyeai.com` | Virtual character/roleplay |
| **MiniMax Platform** | `platform.minimaxi.com` | API access for developers |

---

## 9. Phased Implementation Plan

### Phase 1: Core Chat (Weeks 1-2)
- [ ] Tauri shell with webview
- [ ] MiniMax API integration (chat + streaming)
- [ ] Basic chat UI (message list, input, dark/light theme)
- [ ] Auth flow (MiniMax account)

### Phase 2: Multimodal (Weeks 3-4)
- [ ] Image upload + vision API
- [ ] Document upload + parsing (PDF, DOCX)
- [ ] Voice input (audio recording → transcription)

### Phase 3: Desktop Features (Weeks 5-6)
- [ ] Floating Ball widget
- [ ] Native file picker integration
- [ ] System notifications
- [ ] App tray / menu bar

### Phase 4: Agentic Coding (Weeks 7-10)
- [ ] Tool definitions (file, bash, git)
- [ ] Sandboxed command execution
- [ ] Task state machine
- [ ] Workspace project management
- [ ] Terminal emulator in-app

### Phase 5: MCP Multi-Agent (Weeks 11-12)
- [ ] Agent registry
- [ ] Task delegation engine
- [ ] Multi-agent coordination UI
- [ ] Result aggregation

### Phase 6: Polish + Platform (Weeks 13-14)
- [ ] macOS app store build
- [ ] Windows build
- [ ] Performance optimization
- [ ] E2E tests
