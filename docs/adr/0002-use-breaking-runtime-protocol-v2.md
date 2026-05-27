# Use a Breaking Runtime Protocol v2

Status: superseded by ADR-0005.

MoonCraft will migrate Runtime Protocol v1 directly to a centralized Runtime Protocol v2 without a long-lived compatibility layer. The protocol will have one authoritative specification and machine-checkable schemas, so Runtime providers, the control plane, admin documentation, and official runtime images do not keep separate interpretations of the same contract. The Project Preview Contract remains part of this protocol and defines a fixed Project Workspace **Preview Entrypoint**, rather than putting preview commands in each Runtime Manifest.
