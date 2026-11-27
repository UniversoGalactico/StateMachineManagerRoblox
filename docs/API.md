# API and contracts

## Definitions and instances

`StateMachine.new({Initial, States, Context?, OnChanged?}) -> Machine` compiles and creates one machine. `StateMachine.compile({Initial, States}) -> Graph`; `graph:Create(context?, onChanged?) -> Machine` reuses the same frozen graph. Graph and machine methods are frozen; no mutable state definitions are retained. `Context`, payloads and callback closures are application-owned references; the library does not copy, validate or serialize them. Two machines with the same context share it by caller choice.

Each state definition accepts:

| Field | Type and meaning |
| --- | --- |
| Transitions | dictionary target -> true or guard function |
| Events | dictionary event -> declared transition target |
| After | `{Seconds = number, Target = string}`; target must be a declared edge |
| Update | `(context, dt, state) -> target?, payload?` |
| Enter | `(context, old, new, payload)` |
| Exit | `(context, old, new, payload)` |

All are optional. Names must be valid UTF-8, 1–128 bytes without ASCII control characters. A constructor rejects unknown fields, invalid definitions, undefined destinations, events/timers pointing to missing edges, nonfinite or negative durations, and non-function callbacks. Constructors throw on invalid configuration; use `pcall` only if handling configuration dynamically. There is no wildcard edge: permissions remain explicit. A self-edge is legal only when explicitly present. Unreachable states are permitted (they may be intentional); constructors do not infer game invariants or verify callback termination.

## Transition semantics

1. Reject destroyed/busy machines, unknown state names, absent edge, or stale token (when applicable).
2. If edge has a guard, run `guard(context, old, target, payload)`. Exactly `true` permits. Any other value rejects. Exception/yield rejects, and state/token/time are unchanged.
3. Commit the target, rotate the opaque token, reset elapsed to zero. A self-edge also commits a new generation.
4. Run old state's `Exit`, new state's `Enter`, and instance `OnChanged`, in that order. All observe the **new** state/token and zero elapsed. Each notification is attempted once even if an earlier one failed. No notification is invoked at creation or destruction.

`Transition`, `Send`, `TransitionIfCurrent`, `SendIfCurrent`, and `Step` return `(ok, code?, detail?)`. `ok` means the operation succeeded; it does not always imply a transition (a successful Step can be a no-op). For transition methods, `true` means committed. In particular:

| Result | Meaning |
| --- | --- |
| `true, nil` | successful operation |
| `true, NOTIFICATION_FAILED, issues` | committed transition; one or more notifications failed |
| `false, GUARD_REJECTED` | guard returned a value other than true |
| `false, CALLBACK_ERROR, errorObject` | pre-commit guard/update exception |
| `false, CALLBACK_YIELDED` | guard/update suspended; cancellation attempted |
| `false, UNKNOWN_STATE` | invalid or unknown target |
| `false, SAME_STATE` | self-edge not explicitly declared |
| `false, TRANSITION_NOT_ALLOWED` | target exists but edge is absent |
| `false, UNKNOWN_EVENT` | no mapping for event in current state |
| `false, STALE_TOKEN` | captured token differs from current generation |
| `false, BUSY` | reentrant mutation of same machine |
| `false, DESTROYED` | permanently disposed machine |
| `false, INVALID_DT` / `TIME_OVERFLOW` | invalid input or elapsed accumulation overflow |

`issues` is a list of `{Stage = "Exit" | "Enter" | "OnChanged", Code = "CALLBACK_ERROR" | "CALLBACK_YIELDED", Detail = errorObject?}` in notification order. Error objects are not coerced to strings. Treat their contents as application-controlled. Example:

```lua
local ok, code, detail = machine:Send("Use", {slot = 1})
if not ok then
    warn("Rejected", code)
elseif code == "NOTIFICATION_FAILED" then
    -- Already committed. Repair application side effects, do not repeat the transition.
    for _, issue in ipairs(detail) do warn(issue.Stage, issue.Code) end
end
```

All mutation methods on the same machine reject reentry while a guard, update or notification runs. Reads are allowed. Independent machines can interact synchronously but cyclic mutations can encounter BUSY. Callback errors do not corrupt the internal state, but external side effects and context changes are not transactional. Never yield, call a yielding Roblox API, create detached tasks inside callbacks, or use an infinite loop. Suspended callback threads are cancelled/closed on a best-effort basis. Callbacks requiring asynchronous work should signal your own controller, which schedules work outside the callback and uses a token for subsequent mutation. Never use this library to validate untrusted client authority.

## Step and timers

`Step(dt)` consumes nonnegative finite simulation time, including zero. It accumulates time with compensated binary64 addition and never decreases elapsed within a generation. Invalid dt or arithmetic overflow leaves the elapsed value unchanged. The public elapsed and timer comparison are rounded binary64 values; no exact-real arithmetic or exact deadline guarantee. `Step(0)` does not advance the clock, but still invokes Update and can trigger a zero or already due timer.

After advancing elapsed, invoke `Update(context, dt, state)` if defined. If it returns a non-nil target, that transition has priority, with the second return value used as payload. Otherwise, if the timer is due, try its target with nil payload. Both use the same explicit edge and guard pipeline. An update error/invalid target returns failure without undoing elapsed. A denied timer is retried on subsequent Steps (including zero); Update still executes first. At most one committed transition per Step. Time beyond a deadline is discarded on commit rather than forwarded through other states. Pausing is simply not calling Step. For real-world deadlines, manage the clock in the application rather than passing simulated time.

`GetElapsed()` returns time in current generation; `GetRemaining()` returns `max(0, duration - elapsed)` or `nil, NO_TIMER`. Both return `nil, DESTROYED` after destruction. `GetTransitions` and `GetEvents` return precompiled immutable sorted arrays (graph-only), or `nil, DESTROYED`. `CanTransition`/`CanSend` are graph-only boolean queries; do not execute guards. Do not treat them as a promise that the following transition will succeed.

## Generation tokens and ownership

`Token()` returns a unique immutable table identity or `nil, DESTROYED`. `IsCurrent(token)` is false for foreign, forged or old tokens. An explicit self transition rotates the token, as does leaving a state and returning. `TransitionIfCurrent`/`SendIfCurrent` check identity and execute the mutation synchronously without a yield boundary. Tokens are local and not serializable; no distributed or networking guarantees. Check token before every external side effect following a yield. `Destroy()` is idempotent, rejects while BUSY, invalidates tokens and drops internal references. It does not destroy application context, instances or connections.

## Optional group

`StateMachineGroup.new()` creates a registry, not an owner. `Add(member)` expects a plain table with a raw `Step` function; normal Machine handles qualify. A custom trusted adapter may implement the same synchronous `(boolean, code?, detail?)` contract. The group captures its Step function at registration. Duplicates reject `ALREADY_ADDED`. `Remove(member)` detaches only; `Has`, `Count`, `Destroy` inspect/clear membership. `Destroy` never destroys members; it rejects while the group is stepping. All group methods are local to this VM.

`group:Step(dt) -> true, summary` if the group tick completed, even if member calls failed. Invalid dt, destroyed group or reentry return `false, code`. Summary has `Attempted`, `Succeeded`, `Failed`, `Warnings`, `RemovedDestroyed`, `Issues`. `Warnings` counts successful member calls with a non-nil code; Issues contains `{Member, Succeeded, Code, Detail?}`. Do not confuse successful Step with a committed transition. Individual errors, yields and malformed return values are isolated (`STEP_ERROR`, `STEP_YIELDED`, `INVALID_STEP_RESULT`, `STEP_REJECTED`). A member returning `false, DESTROYED` is detached automatically if its registration is still current. Removal/addition is safe during callbacks: a removed member not yet reached is skipped; a newly added/re-added member waits until next tick. Order is insertion order. Removed records drop references immediately; tombstones are compacted amortized, without unbounded stale registries. No hidden background loops. Group protective coroutine overhead is intentional; use direct Step for hot paths when appropriate.

## Integration and scope

Keep authoritative machine updates on the server where gameplay requires it. Clients can use separate machines for UI; sync state via your own validated protocol. No network replication, pathfinding, animation, persistence, hierarchical statecharts, concurrency locks, or automated rate limiting are included. Compose multiple independent machines for orthogonal concerns (movement/combat/UI). Keep graph definitions in code, not untrusted input. No limits on NPC counts are advertised; memory/time depend on workload and Roblox scheduling. Test your game, including callback side effects.
