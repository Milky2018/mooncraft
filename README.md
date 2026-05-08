# Mooncraft

Mooncraft is a chat-first app builder for MoonBit applications.

Users describe what they want, Mooncraft updates the app, and the browser shows a live preview. Code stays hidden in the default product flow.

## What It Does

- Create and manage projects.
- Build apps through a chat workspace.
- Show the generated app in a live preview panel.
- Keep project ownership separated between signed-in users.
- Run project builds through an admin-managed OpenRouter key pool.

## Run Locally

```bash
just build
just serve
```

Then open:

```text
http://localhost:8080
```

Useful checks:

```bash
just smoke
moon test
```

## Deployment

Docker Compose is the supported path for test and production deployments. Start with:

- [Docker Compose Deployment](docs/docker-compose-deploy.md)
- [EC2 Deployment Notes](docs/deploy-ec2.md)

## Project Docs

- [Product PRD](docs/prd.md)
- [Architecture](docs/architecture.md)
- [Website Prototype](docs/website-prototype.md)
- [Agent Docs Plan](docs/agent-docs.md)
- [Issue Tracker](docs/issue-tracker.md)
