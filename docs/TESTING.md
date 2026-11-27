# Verification and limitations

## Reproduce

- `python3 tests/run.py --luau /path/to/luau --optimization 2`: regression suites, including 100,000 graph transitions, 100,000 mixed guarded event/timer actions and 2,000 group ticks with membership churn per optimization. CI repeats at O0, O1, O2.
- `python3 tests/typecheck.py --analyzer /path/to/luau-analyze`: strict analysis of both modules using a CLI-only `task` declaration; it is not a substitute for Studio's Roblox-aware analyzer.
- `python3 tests/mutation.py --luau /path/to/luau`: selected deliberately broken implementations must be rejected by regression tests. A compiler failure or timeout does not count as detection.
- `python3 tests/benchmark.py --luau /path/to/luau --out bench.json`: optional local microbenchmark. Do not interpret CLI results as Roblox performance or supported entity counts.
- `tests/studio_smoke.server.lua`: 15 Studio-only checks including real `task.wait` cancellation, Heartbeat and group integration. No DataStore or other API access is required. The maintainer reported 15/15 passing in Roblox Studio on rc.2 (2026-11-27); this is a reported result, not independently collected telemetry.

## Adversarial numerical audit

`python3 tests/luauproof_attack.py --luauproof /path/to/luauproof --seed 32031 --out audit.json` (repeat seed 32032). Requires the external pinned LuauProof 3.20 grammar, operand generator, rational binary64 oracle and Luau CLI. The external toolkit is not distributed or required by this library. The script verifies relevant tool hashes. [Evidence](../tests/evidence/rc2/) includes two final campaigns and the pre-fix campaign. To reconstruct the exact earlier source, apply pre_fix_source.diff to a copy of the final module and verify the recorded SHA-256. This is finite testing, not formal verification.

The corrected pre-fix campaign found two zero-time clock discrepancies per optimization: compensated addition could advance elapsed on `Step(0)` after a rounding residual. The minimized witness is `Step(0.000009)`, `Step(0.00002)`, then `Step(0)`. The fix bypasses arithmetic for zero steps while still executing Update/timer logic. An earlier harness error (extra return value from string.unpack in a generated list) was fixed before the matched pre-fix comparison.

The final two seeds record 1,268,640 checks across O0/O1/O2 with zero observed discrepancies; the total includes arithmetic-oracle checks, several assertions per generated input and repeated inputs across optimizations. Long-sum checks use an explicit two-ULP tolerance against exact rational sums, not a claim of exact addition. Evidence hashes identify the code tested. The selected mutation campaign detects 15/15 deliberate semantic defects. Benchmark observations are scoped to this local environment, five alternating trials per operation; there is no server capacity claim.

## Audit boundary

CLI testing cannot establish Roblox scheduler cancellation, game-specific side effects, frame rate, networking behavior, or performance at production scale. The group is optional and incurs coroutine overhead for adapter isolation. Neither module provides a network lock, transactional callbacks, watchdog for infinite loops, or hierarchical statecharts. Integrators own runtime scheduling, validation, error handling and cleanup.

## Stable release

The v3.0.0 runtime modules differ from the tested rc.2 modules only in their VERSION strings. Historical evidence retains the original source hashes. CI reruns strict analysis, regression and selected mutation tests on the final release. Studio smoke tests do not establish capacity, production performance or behavior in all games.
