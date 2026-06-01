# MoonCraft Runtime Service

This package builds the official MoonCraft Runtime Protocol v3 HTTP service.

It is compiled to a native binary and embedded in the official Runtime image.
The service exposes `/health`, `/init`, `/exec`, `/runs/:run_id`,
`/runs/:run_id/events`, and `/preview` on port `8080`.
