# Examples

This directory contains runnable reference projects and platform seed material.

## Project Seeds

`project-seeds/native-mocket` is copied into every new generated project
workspace before the first builder turn. It is not a user-facing template picker;
it is the minimal valid MoonBit native preview contract that gives the builder a
working root project to replace.

Keep seed projects runnable with `moon -C <seed-dir> check`, `moon -C <seed-dir>
build --target native`, and `moon -C <seed-dir> test`.
