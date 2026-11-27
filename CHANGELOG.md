# Changelog

## 3.0.0 — 2026-11-27

- Generic typed FSM, reusable immutable graph, events, timers, explicit self-transitions, guarded transitions, post-commit notifications and opaque generation tokens.
- Optional mutation-safe group, examples and Studio smoke tests.
- 33 regression suites at O0/O1/O2, 15 selected semantic mutations detected, finite external numerical audit on rc.2, and maintainer-reported Studio smoke test 15/15.
- Breaking change from the old NPC registry. Final runtime modules differ from rc.2 only in version strings. No claims of formal verification or production capacity.
