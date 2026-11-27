--!strict
-- Deterministic, caller-stepped finite state machines. No automatic tasks or services.
export type Guard = (context: any, from: string, to: string, payload: any) -> boolean
export type Update = (context: any, dt: number, state: string) -> (string?, any?)
export type Notification = (context: any, from: string, to: string, payload: any) -> ()
export type StateDefinition = {
	Transitions: {[string]: (true | Guard)}?,
	Events: {[string]: string}?,
	After: {Seconds: number, Target: string}?,
	Update: Update?,
	Enter: Notification?,
	Exit: Notification?,
}
export type Definition = {Initial: string, States: {[string]: StateDefinition}}
export type Config = Definition & {Context: any?, OnChanged: Notification?}
export type Token = {}
export type Machine = {
	GetState: (self: Machine) -> (string?, string?),
	GetElapsed: (self: Machine) -> (number?, string?),
	GetRemaining: (self: Machine) -> (number?, string?),
	GetTransitions: (self: Machine) -> ({string}?, string?),
	GetEvents: (self: Machine) -> ({string}?, string?),
	Token: (self: Machine) -> (Token?, string?),
	IsCurrent: (self: Machine, token: any) -> boolean,
	CanTransition: (self: Machine, target: string) -> boolean,
	CanSend: (self: Machine, event: string) -> boolean,
	Transition: (self: Machine, target: string, payload: any?) -> (boolean, string?, any?),
	TransitionIfCurrent: (self: Machine, token: Token, target: string, payload: any?) -> (boolean, string?, any?),
	Send: (self: Machine, event: string, payload: any?) -> (boolean, string?, any?),
	SendIfCurrent: (self: Machine, token: Token, event: string, payload: any?) -> (boolean, string?, any?),
	Step: (self: Machine, dt: number) -> (boolean, string?, any?),
	Destroy: (self: Machine) -> (boolean, string?),
}
export type Graph = {Create: (self: Graph, context: any?, onChanged: Notification?) -> Machine}

type CompiledState = {
	Transitions: {[string]: (true | Guard)},
	Events: {[string]: string},
	TransitionNames: {string},
	EventNames: {string},
	After: {Seconds: number, Target: string}?,
	Update: Update?,
	Enter: Notification?,
	Exit: Notification?,
}
type States = {[string]: CompiledState}
type Failure = {Stage: string, Code: string, Detail: any?}
local StateMachine = {VERSION = "3.0.0-rc.2"}

local function plain(value: any): boolean
	return type(value) == "table" and getmetatable(value) == nil
end
local function nameValid(name: any): boolean
	return type(name) == "string" and #name > 0 and #name <= 128
		and utf8.len(name) ~= nil and string.find(name, "%c") == nil
end
local function durationValid(n: any): boolean
	return type(n) == "number" and n == n and n >= 0 and n < math.huge
end
local function keys(value: {[string]: any}): {string}
	local result = {}
	for key in pairs(value) do table.insert(result, key) end
	table.sort(result)
	table.freeze(result)
	return result
end

-- No callback can suspend a transition. Cancellation cannot undo user side effects.
local function invoke(fn: any, ...: any): (boolean, any, any?)
	local thread = coroutine.create(fn)
	local ok, result, payload = coroutine.resume(thread, ...)
	if coroutine.status(thread) ~= "dead" then
		if task and task.cancel then pcall(task.cancel, thread) end
		pcall(coroutine.close, thread)
		return false, "CALLBACK_YIELDED", nil
	end
	if not ok then return false, "CALLBACK_ERROR", result end
	return true, result, payload
end

local OPTIONS: {[string]: boolean} = {Initial=true, States=true, Context=true, OnChanged=true}
local GRAPH_OPTIONS: {[string]: boolean} = {Initial=true, States=true}
local STATE_OPTIONS: {[string]: boolean} = {Transitions=true, Events=true, After=true, Update=true, Enter=true, Exit=true}
local TIMER_OPTIONS: {[string]: boolean} = {Seconds=true, Target=true}
table.freeze(OPTIONS)
table.freeze(GRAPH_OPTIONS)
table.freeze(STATE_OPTIONS)
table.freeze(TIMER_OPTIONS)
local function validateOptions(value: any, allowed: {[string]: boolean}, code: string)
	assert(plain(value), "INVALID_TABLE")
	for key in next, value do assert(allowed[key] == true, code) end
end

-- Compile once, then share the immutable graph across independent instances.
local function compile(config: any, direct: boolean): (States, string)
	validateOptions(config, if direct then OPTIONS else GRAPH_OPTIONS, "UNKNOWN_OPTION")
	assert(plain(config.States), "INVALID_STATES")
	local states: States = {}
	for name, definition in next, config.States do
		assert(type(name) == "string" and nameValid(name) and plain(definition), "INVALID_STATE")
		local stateName: string = name
		validateOptions(definition, STATE_OPTIONS, "UNKNOWN_STATE_OPTION")
		for _, field in ipairs({"Update", "Enter", "Exit"}) do
			assert(definition[field] == nil or type(definition[field]) == "function", "INVALID_CALLBACK")
		end
		local edges: {[string]: (true | Guard)} = {}
		if definition.Transitions ~= nil then
			assert(plain(definition.Transitions), "INVALID_TRANSITIONS")
			for target, guard in next, definition.Transitions do
				assert(type(target) == "string" and nameValid(target) and (guard == true or type(guard) == "function"), "INVALID_TRANSITION")
				edges[target] = guard :: (true | Guard)
			end
		end
		local events: {[string]: string} = {}
		if definition.Events ~= nil then
			assert(plain(definition.Events), "INVALID_EVENTS")
			for event, target in next, definition.Events do
				assert(type(event) == "string" and type(target) == "string" and nameValid(event) and nameValid(target) and edges[target] ~= nil, "INVALID_EVENT")
				events[event] = target
			end
		end
		local after: {Seconds: number, Target: string}? = nil
		if definition.After ~= nil then
			validateOptions(definition.After, TIMER_OPTIONS, "UNKNOWN_TIMER_OPTION")
			assert(durationValid(definition.After.Seconds), "INVALID_DURATION")
			assert(nameValid(definition.After.Target) and edges[definition.After.Target] ~= nil, "INVALID_TIMER_TARGET")
			after = {Seconds=definition.After.Seconds, Target=definition.After.Target}
			table.freeze(after)
		end
		table.freeze(edges)
		table.freeze(events)
		local state: CompiledState = {
			Transitions=edges, Events=events, TransitionNames=keys(edges), EventNames=keys(events),
			After=after, Update=definition.Update, Enter=definition.Enter, Exit=definition.Exit,
		}
		table.freeze(state)
		states[stateName] = state
	end
	assert(nameValid(config.Initial) and states[config.Initial], "INVALID_INITIAL_STATE")
	for _, state in pairs(states) do
		for target in pairs(state.Transitions) do assert(states[target], "UNKNOWN_TRANSITION_TARGET") end
	end
	table.freeze(states)
	return states, config.Initial
end

local function create(statesInput: States, initial: string, initialContext: any, changed: Notification?): Machine
	assert(changed == nil or type(changed) == "function", "INVALID_ON_CHANGED")
	local states: States? = statesInput
	local context = initialContext
	local onChanged = changed
	local current: string? = initial
	local generation: Token? = table.freeze({})
	local elapsed = 0
	-- Positive-step compensated sum. The public value is binary64, not an exact clock.
	local correction = 0
	local busy = false
	local destroyed = false
	local machine = {} :: any
	local function state(): CompiledState
		return (states :: States)[current :: string]
	end
	local function ready(): (boolean, string?)
		if destroyed then return false, "DESTROYED" end
		if busy then return false, "BUSY" end
		return true, nil
	end
	local function transition(target: any, payload: any): (boolean, string?, any?)
		if not nameValid(target) or not (states :: States)[target] then return false, "UNKNOWN_STATE", nil end
		local previous = current :: string
		local old = state()
		local guard = old.Transitions[target]
		if guard == nil then
			return false, if target == previous then "SAME_STATE" else "TRANSITION_NOT_ALLOWED", nil
		end
		if guard ~= true then
			local ok, result, detail = invoke(guard :: Guard, context, previous, target, payload)
			if not ok then return false, result, detail end
			if result ~= true then return false, "GUARD_REJECTED", nil end
		end
		-- Commit first. Each notification observes the new state and token.
		current = target
		generation = table.freeze({})
		elapsed, correction = 0, 0
		local failures: {Failure}? = nil
		local function notify(stage: string, fn: Notification?)
			if fn == nil then return end
			local ok, code, detail = invoke(fn, context, previous, target, payload)
			if not ok then
				if failures == nil then failures = {} end
				table.insert(failures :: {Failure}, {Stage=stage, Code=code, Detail=detail})
			end
		end
		notify("Exit", old.Exit)
		notify("Enter", state().Enter)
		notify("OnChanged", onChanged)
		if failures ~= nil then return true, "NOTIFICATION_FAILED", failures end
		return true, nil, nil
	end
	local function eventTarget(event: any): (string?, string?)
		if not nameValid(event) then return nil, "UNKNOWN_EVENT" end
		local target = state().Events[event]
		if target == nil then return nil, "UNKNOWN_EVENT" end
		return target, nil
	end
	local function runTransition(target: any, payload: any): (boolean, string?, any?)
		busy = true
		local ok, code, detail = transition(target, payload)
		busy = false
		return ok, code, detail
	end

	function machine:GetState(): (string?, string?)
		if destroyed then return nil, "DESTROYED" end
		return current, nil
	end
	function machine:GetElapsed(): (number?, string?)
		if destroyed then return nil, "DESTROYED" end
		return elapsed, nil
	end
	function machine:GetRemaining(): (number?, string?)
		if destroyed then return nil, "DESTROYED" end
		local timer = state().After
		if timer == nil then return nil, "NO_TIMER" end
		return math.max(0, timer.Seconds - elapsed), nil
	end
	function machine:GetTransitions(): ({string}?, string?)
		if destroyed then return nil, "DESTROYED" end
		return state().TransitionNames, nil
	end
	function machine:GetEvents(): ({string}?, string?)
		if destroyed then return nil, "DESTROYED" end
		return state().EventNames, nil
	end
	function machine:Token(): (Token?, string?)
		if destroyed then return nil, "DESTROYED" end
		return generation, nil
	end
	function machine:IsCurrent(token: any): boolean
		return not destroyed and rawequal(token, generation)
	end
	function machine:CanTransition(target: any): boolean
		return not destroyed and nameValid(target) and state().Transitions[target] ~= nil
	end
	function machine:CanSend(event: any): boolean
		return not destroyed and nameValid(event) and state().Events[event] ~= nil
	end
	function machine:Transition(target: any, payload: any): (boolean, string?, any?)
		local ok, err = ready()
		if not ok then return false, err, nil end
		return runTransition(target, payload)
	end
	function machine:TransitionIfCurrent(token: any, target: any, payload: any): (boolean, string?, any?)
		local ok, err = ready()
		if not ok then return false, err, nil end
		if not rawequal(token, generation) then return false, "STALE_TOKEN", nil end
		return runTransition(target, payload)
	end
	function machine:Send(event: any, payload: any): (boolean, string?, any?)
		local ok, err = ready()
		if not ok then return false, err, nil end
		local target, eventErr = eventTarget(event)
		if target == nil then return false, eventErr, nil end
		return runTransition(target, payload)
	end
	function machine:SendIfCurrent(token: any, event: any, payload: any): (boolean, string?, any?)
		local ok, err = ready()
		if not ok then return false, err, nil end
		if not rawequal(token, generation) then return false, "STALE_TOKEN", nil end
		local target, eventErr = eventTarget(event)
		if target == nil then return false, eventErr, nil end
		return runTransition(target, payload)
	end
	function machine:Step(dt: any): (boolean, string?, any?)
		local ok, err = ready()
		if not ok then return false, err, nil end
		if not durationValid(dt) then return false, "INVALID_DT", nil end
		-- Compensated addition (Kahan). For nonnegative steps, roundoff can
		-- occasionally make the corrected sum smaller; never move elapsed back.
		-- Zero time is a legitimate update, but must not consume rounding debt.
		if dt > 0 then
			local adjusted = dt - correction
			local nextElapsed = elapsed + adjusted
			if not durationValid(nextElapsed) then return false, "TIME_OVERFLOW", nil end
			if nextElapsed >= elapsed then
				correction = (nextElapsed - elapsed) - adjusted
				elapsed = nextElapsed
			else
				correction -= dt
			end
		end
		local definition = state()
		local update = definition.Update
		local target: any = nil
		local payload: any = nil
		busy = true
		if update ~= nil then
			local ran, result, detail = invoke(update, context, dt, current)
			if not ran then busy = false; return false, result, detail end
			target, payload = result, detail
		end
		-- An explicit Update target has priority; at most one transition per Step.
		local timer = definition.After
		if target == nil and timer ~= nil and elapsed >= timer.Seconds then target, payload = timer.Target, nil end
		if target == nil then busy = false; return true, nil, nil end
		local success, code, detail = transition(target, payload)
		busy = false
		return success, code, detail
	end
	function machine:Destroy(): (boolean, string?)
		if destroyed then return true, nil end
		if busy then return false, "BUSY" end
		destroyed = true
		current, generation, states, context, onChanged = nil, nil, nil, nil, nil
		return true, nil
	end
	table.freeze(machine)
	return machine :: Machine
end

function StateMachine.compile(definition: Definition): Graph
	local states, initial = compile(definition, false)
	local graph = {} :: any
	function graph:Create(context: any, onChanged: Notification?): Machine
		return create(states, initial, context, onChanged)
	end
	table.freeze(graph)
	return graph :: Graph
end

function StateMachine.new(config: Config): Machine
	local states, initial = compile(config, true)
	return create(states, initial, config.Context, config.OnChanged)
end
return table.freeze(StateMachine)
