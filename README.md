# StateMachineManager for Roblox

A reusable finite-state machine for rounds, NPCs, abilities, interactions, menus and more. **3.0.0-rc.2** is a release candidate. MIT; no runtime dependencies, automatic loops or networking.

## Start in one minute

Copy [StateMachineManagerRoblox.lua](StateMachineManagerRoblox.lua) into a ModuleScript named `StateMachine`.

```lua
local StateMachine = require(script.Parent.StateMachine)
local machine = StateMachine.new({
    Initial = "Ready",
    States = {
        Ready = {
            Transitions = {Cooldown = true},
            Events = {Use = "Cooldown"},
        },
        Cooldown = {
            Transitions = {Ready = true},
            After = {Seconds = 3, Target = "Ready"},
        },
    },
})

assert(machine:Send("Use"))
assert(machine:Step(3)) -- caller supplies simulation time
print(machine:GetState()) -- Ready
```

For a timed game, call `Step(dt)` from your existing game loop or Heartbeat. For event-driven logic, you may never need `Step`. Destroy a machine when you no longer need it.

## Useful building blocks

| Feature | Use |
| --- | --- |
| `Transition(target, payload?)` | Explicit legal edge; optional synchronous guard |
| `Send(event, payload?)` | Map game events to state transitions |
| `After = {Seconds, Target}` | One timed edge per state; no spawned timer |
| `Update(context, dt, state)` | Return an optional target and payload |
| `Enter`, `Exit`, `OnChanged` | Synchronous notifications after commit |
| `Token()` / `TransitionIfCurrent(...)` / `SendIfCurrent(...)` | Reject stale asynchronous work, even after leaving and returning to the same state |
| `compile(definition):Create(context?, onChanged?)` | Reuse an immutable graph for many entities |
| `GetState`, `GetElapsed`, `GetRemaining`, `GetTransitions`, `GetEvents` | Inspect current state and graph |

See [API and contracts](docs/API.md) · [Examples](examples/) · [Testing](docs/TESTING.md) · [AI guide](AGENTS.md).

### Many NPCs or machines?

Optional: install [StateMachineGroup.lua](StateMachineGroup.lua) as `StateMachineGroup`. Call `group:Add(machine)` and `group:Step(dt)` from one existing loop. The group preserves insertion order, skips removed members, defers new members until the next tick and reports individual failures. Removing a machine does not destroy it. For hot paths, direct `Step` avoids the additional group overhead. [NPC integration](examples/NPCGroup.server.lua).

### Safe asynchronous work

```lua
local token = machine:Token()
-- Your own asynchronous operation goes here.
-- Do not rely on the state name alone: it may have changed away and back.
if token then
    local ok, code = machine:SendIfCurrent(token, "Use")
    if not ok then warn(code) end
end
```

Tokens are local generation identities, not network locks. For other asynchronous side effects, check `IsCurrent(token)` immediately before committing them.

### Important contracts

- Only listed edges are legal. Use `true` or a guard returning exactly `true`. An explicitly listed self-edge reenters the state and resets time/token.
- Guards and callbacks must not yield, reenter mutation methods, or spawn detached side effects. A callback may read machine state. Side effects cannot be rolled back.
- `true, "NOTIFICATION_FAILED", issues` means the transition **already committed**. Never blindly retry it. See [error handling](docs/API.md).
- Timers use caller-supplied finite, nonnegative `dt`; no wall-clock, catch-up or real-time guarantee. At most one transition per `Step`; overshoot is discarded on commit.
- Initial construction and destruction do not invoke Enter/Exit. The caller owns setup and teardown.
- Breaking change from the original public NPC registry. The legacy module is [available in Git history](https://github.com/UniversoGalactico/StateMachineManagerRoblox/blob/32542f3db8aae455f7d8c0b66d656b436fc7ba5c/StateMachineManagerRoblox.lua). rc.2 adds features and structured post-commit errors relative to rc.1. No compatibility shim for the old global registry.

MIT — [LICENSE](LICENSE).
