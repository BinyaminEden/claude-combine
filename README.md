# claude-combine

A unified Claude Code plugin that merges the best of two community projects:

- **[superpowers](https://github.com/obra/superpowers)** by Jesse Vincent — TDD, systematic debugging, planning workflows, code review, and collaboration patterns
- **[everything-claude-code](https://github.com/affaan-m/everything-claude-code)** by Affaan Mustafa — agents, continuous learning, session management, hooks, rules, and productivity tooling

## Install

```bash
# From GitHub marketplace
/plugin marketplace add YOUR_USERNAME/claude-combine
/plugin install claude-combine@YOUR_USERNAME

# Or point directly at the local directory
claude --plugin-dir ~/Documents/personal/claude-combine
```

## What's Included

### Skills (35)

**From superpowers (14):** brainstorming, writing-plans, executing-plans, test-driven-development, systematic-debugging, requesting-code-review, receiving-code-review, dispatching-parallel-agents, subagent-driven-development, using-git-worktrees, finishing-a-development-branch, verification-before-completion, using-superpowers, writing-skills

**From everything-claude-code (21):** deep-research, strategic-compact, continuous-learning, continuous-learning-v2, api-design, database-migrations, docker-patterns, mcp-server-patterns, security-review, security-scan, frontend-patterns, backend-patterns, postgres-patterns, prompt-optimizer, deployment-patterns, e2e-testing, coding-standards, python-patterns, python-testing, java-coding-standards, jpa-patterns

### Agents (11)

**From superpowers:** code-reviewer

**From everything-claude-code:** architect, security-reviewer, database-reviewer, build-error-resolver, refactor-cleaner, doc-updater, e2e-runner, java-build-resolver, java-reviewer, python-reviewer

### Commands (18)

**From superpowers (3):** brainstorm, write-plan, execute-plan

**From everything-claude-code (15):** learn, learn-eval, save-session, resume-session, sessions, checkpoint, instinct-export, instinct-import, instinct-status, skill-create, skill-health, update-docs, verify, build-fix, prompt-optimize

### Hooks

Merged hook configuration with superpowers session-start running first (injects skill framework), followed by ECC session context loader. All ECC lifecycle hooks included:

| Lifecycle     | Hooks                                                                 |
|---------------|-----------------------------------------------------------------------|
| SessionStart  | superpowers skill injection, ECC context loader                       |
| PreToolUse    | git push reminder, doc file warning, compact suggestion, learning observer |
| PostToolUse   | PR logger, build analyzer, quality gate, auto-formatter, TypeScript checker, console.log warning, learning observer |
| PreCompact    | State saver                                                           |
| Stop          | console.log check, session persister, pattern evaluator, cost tracker |
| SessionEnd    | Lifecycle marker                                                      |

### Rules

- `rules/common/` — 9 files (agents, coding style, development workflow, git, hooks, patterns, performance, security, testing)
- `rules/typescript/` — 5 files (coding style, hooks, patterns, security, testing)
- `rules/python/` — 5 files (coding style, hooks, patterns, security, testing)

### Hook Profiles

ECC hooks use a flag-based profile system. Set `ECC_HOOK_PROFILE` to control which hooks run:

| Profile    | Description                          |
|------------|--------------------------------------|
| `minimal`  | Session management only              |
| `standard` | + quality gates, formatting, learning |
| `strict`   | + all warnings and reminders         |

Default is `standard`. Set via: `export ECC_HOOK_PROFILE=strict`

## Attribution

This plugin combines content from two MIT-licensed projects. See [LICENSE](./LICENSE) for details.

- **superpowers** — Copyright (c) 2025 Jesse Vincent
- **everything-claude-code** — Copyright (c) 2026 Affaan Mustafa
