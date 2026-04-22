# MoonBit Cloud

MoonBit Cloud is an agent-first platform for building backend applications through conversation. End users should not need to know which language or framework powers their software. They describe what they want, the agent builds it, and the platform runs and deploys it.

The implementation target is MoonBit-first:

- user applications are written in MoonBit
- templates and platform-facing SDKs are written in MoonBit
- missing ecosystem pieces should be built as MoonBit libraries when needed

The first version is a **local single-user prototype** focused on one narrow loop:

1. pick a template or describe an app in chat
2. let the agent create or modify the project
3. run the app locally
4. inspect logs and behavior
5. deploy the app to a local prototype endpoint

## Product Direction

- Target user: AI-first indie builders
- Product surface: browser-only, chat-first workspace
- App scope: HTTP APIs only
- User experience: code is an internal artifact, not the primary interface
- Flagship demo: a multi-tenant todo app with durable storage
- Success target: one demo video and twenty reusable templates

## What This Is Not

MoonBit Cloud v1 is not:

- a general-purpose cloud IDE
- a Replit-style terminal workspace
- a collaboration product
- a production-ready multi-tenant hosting system
- a billing, team, or enterprise platform

## Core Documents

- [Product PRD](/Users/zhengyu/Documents/projects/moonbitcloud/docs/prd.md)
- [Architecture](/Users/zhengyu/Documents/projects/moonbitcloud/docs/architecture.md)
- [Agent Docs Plan](/Users/zhengyu/Documents/projects/moonbitcloud/docs/agent-docs.md)
- [Templates Roadmap](/Users/zhengyu/Documents/projects/moonbitcloud/docs/templates-roadmap.md)
- [Issue Tracker](/Users/zhengyu/Documents/projects/moonbitcloud/docs/issue-tracker.md)

## Suggested Repo Shape

```text
moonbitcloud/
├── README.md
├── docs/
│   ├── prd.md
│   ├── architecture.md
│   ├── agent-docs.md
│   ├── templates-roadmap.md
│   └── issue-tracker.md
├── apps/
│   └── web/                  # chat-first product surface
├── services/
│   ├── control-plane/        # projects, conversations, builds, deployments
│   └── runner/               # compile and execute MoonBit apps
├── packages/
│   └── sdk/                  # request, response, context contracts
├── knowledge/                # agent-readable platform docs
└── examples/                 # working templates and sample apps
```

## What To Build First

1. Freeze the app runtime contract for MoonBit HTTP handlers.
2. Prove the runner can compile and execute a template app locally.
3. Build a chat-first web shell with preview, logs, and deploy actions.
4. Write the first knowledge documents from a working template.

The next concrete work queue lives in [docs/issue-tracker.md](/Users/zhengyu/Documents/projects/moonbitcloud/docs/issue-tracker.md).
