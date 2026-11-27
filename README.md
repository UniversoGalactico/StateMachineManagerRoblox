# StateMachineManager for Roblox

A small finite-state machine for NPCs, rounds, menus, abilities and other game logic. **3.0.0-rc.1** is a release candidate. MIT; no dependencies or automatic loops.

## Install

Paste [StateMachineManagerRoblox.lua](StateMachineManagerRoblox.lua) into a ModuleScript named StateMachine.

```lua
local StateMachine = require(script.Parent.StateMachine)
local machine = StateMachine.new({
    Initial = "Idle",
    States = {
        Idle = {Transitions = {Chase = true}},
        Chase = {Transitions = {Idle = true, Attack = true}},
        Attack = {Transitions = {Idle = true}},
    },
    OnChanged = function(context, old, new)
        print(old, "->", new)
    end,
})

assert(machine:Transition("Chase"))
print(machine:GetState()) -- Chase
machine:Destroy()
```

Only listed transitions are allowed. Replace `true` with a synchronous guard function returning exactly true to permit the transition. Optional state Update functions run only when you call Step(dt). They may return a target state or nil.

| API | Meaning |
| --- | --- |
| new(config) | independent machine |
| GetState() | current state |
| Transition(target, payload?) | guarded transition |
| CanTransition(target) | graph-only check, not guard evaluation |
| Token() / IsCurrent(token) | opaque state-generation identity |
| TransitionIfCurrent(token, target, payload?) | reject stale async work |
| Step(dt) | optional update |
| Destroy() | invalidate machine and release references |

See [API and contracts](docs/API.md), [NPC example](examples/NPC.server.lua), [tests](tests/), and [AI guide](AGENTS.md).

**Breaking change:** the old NPC registry API is not retained. The [legacy module](https://github.com/UniversoGalactico/StateMachineManagerRoblox/blob/32542f3db8aae455f7d8c0b66d656b436fc7ba5c/StateMachineManagerRoblox.lua) remains available in history. Applications own their update connections and NPC cleanup.

Callbacks must not yield or reenter mutation methods. Callback errors are observable; a failed post-commit notification does not roll back the transition. No automatic networking, rate limiting or performance certification.
