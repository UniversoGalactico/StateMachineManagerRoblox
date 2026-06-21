StateMachineManager
A high-performance state engine for Roblox NPCs. Built to handle 100+ concurrent entities with zero memory leaks and atomic state transitions.

API Reference:

StateMachineManager.Register(model: Instance, states: table, initialState: string, data: table)
StateMachineManager.SetState(model: Instance, stateName: string)
StateMachineManager.Unregister(model: Instance)

Technical Specs:

Concurrency: Per-NPC mutex prevents race conditions during state transitions.

Queuing: Pending state requests are automatically queued when the NPC is busy.

Rate Limiting: Protects CPU cycles by throttling state-change frequency.

Lifecycle: Auto-cleanup via Instance.Destroying hook + heartbeat-only processing (no orphan loops).

Quick Start:



local states = {
    idle = { onEnter = function() ... end },
    attack = { onEnter = function() ... end }
}

StateMachineManager.Register(myNPC, states, "idle", {Target = nil})
StateMachineManager.SetState(myNPC, "attack")
