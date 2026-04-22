# Runner Service

This service is responsible for compiling and executing user MoonBit code.

Initial responsibilities:

- accept a source snapshot
- compile a MoonBit handler
- execute a request
- return response, logs, and build errors

Keep this boundary explicit even in local development.
