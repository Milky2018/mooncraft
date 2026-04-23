---
title: Template Invariants
summary: Platform rules that official templates must preserve
applies_to:
  - templates
  - agent-edits
editable_files:
  - templates
  - examples
  - knowledge/templates
entrypoints: []
validation:
  - template smoke test
status: draft
---

# When To Use

Use this document when creating a new template or when letting the agent modify an existing template.

# Invariants

- Every official template must remain runnable through the standard runner flow.
- Every template must keep a recognizable project structure.
- Required entrypoints must not be renamed without updating the contract docs.
- Multi-tenant templates must preserve explicit tenant scoping.
- A template should prefer one canonical pattern over several competing patterns.

# Required Artifacts

Every official template should eventually include:

- runnable source
- validation command or smoke test
- matching knowledge document
- short summary of what the template supports

# Do Not Do This

- Do not let the agent freely reorganize template structure on every edit.
- Do not merge unrelated platform experiments into a template.
- Do not call a template official if it has no validation path.

# Validation

- Run the template smoke check.
- Verify the expected entrypoints still exist.
- Verify the related knowledge docs still describe the actual layout.

# Related Docs

- [App Model](../concepts/app-model.md)
- [HTTP Handler Contract](../contracts/http-handler.md)
- [Tenant Model](../contracts/tenant-model.md)
