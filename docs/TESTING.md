# Tests and limitations

Run python3 tests/run.py --luau /path/to/luau --optimization 2. CI repeats at O0, O1, O2. The suites cover graph validation, mutation isolation, guard failures, post-commit notification failure, reentrancy, stale tokens, update errors, destruction, and a seeded graph model with 100,000 transitions per optimization. These are CLI tests; actual Studio task cancellation, NPC integration and performance remain separate validation gates. No measured NPC capacity or production guarantees.
