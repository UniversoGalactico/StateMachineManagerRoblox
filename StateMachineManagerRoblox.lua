--!nonstrict
-- A synchronous finite-state machine. No services, global registry or background tasks.
local StateMachine = {VERSION="3.0.0-rc.1"}

local function plain(value)
	return type(value)=="table" and getmetatable(value)==nil
end

local function nameValid(name)
	return type(name)=="string" and #name>0 and #name<=128
end

-- A callback is allowed to finish synchronously, never to suspend the machine.
-- Cancellation cannot undo side effects already performed by user code.
local function invoke(fn,...)
	local thread=coroutine.create(fn)
	local ok,result=coroutine.resume(thread,...)
	if coroutine.status(thread)~="dead" then
		if task and task.cancel then pcall(task.cancel,thread) end
		pcall(coroutine.close,thread)
		return false,"CALLBACK_YIELDED"
	end
	if not ok then return false,"CALLBACK_ERROR",result end
	return true,result
end

local OPTIONS=table.freeze({Initial=true,States=true,Context=true,OnChanged=true})
local STATE_OPTIONS=table.freeze({Transitions=true,Update=true})

function StateMachine.new(config)
	assert(plain(config),"INVALID_CONFIG")
	for key in next,config do assert(OPTIONS[key],"UNKNOWN_OPTION") end
	assert(plain(config.States),"INVALID_STATES")
	assert(config.OnChanged==nil or type(config.OnChanged)=="function","INVALID_ON_CHANGED")
	local states={}
	for name,definition in next,config.States do
		assert(nameValid(name) and plain(definition),"INVALID_STATE")
		for key in next,definition do assert(STATE_OPTIONS[key],"UNKNOWN_STATE_OPTION") end
		assert(definition.Update==nil or type(definition.Update)=="function","INVALID_UPDATE")
		local edges={}
		if definition.Transitions~=nil then
			assert(plain(definition.Transitions),"INVALID_TRANSITIONS")
			for target,guard in next,definition.Transitions do
				assert(nameValid(target) and (guard==true or type(guard)=="function"),"INVALID_TRANSITION")
				assert(target~=name,"SELF_TRANSITION_NOT_SUPPORTED")
				edges[target]=guard
			end
		end
		states[name]={Transitions=table.freeze(edges),Update=definition.Update}
	end
	assert(nameValid(config.Initial) and states[config.Initial],"INVALID_INITIAL_STATE")
	for _,definition in pairs(states) do
		for target in pairs(definition.Transitions) do
			assert(states[target],"UNKNOWN_TRANSITION_TARGET")
		end
		table.freeze(definition)
	end
	table.freeze(states)
	local context=config.Context
	local onChanged=config.OnChanged
	local current=config.Initial
	local generation=table.freeze({})
	local busy=false
	local destroyed=false
	local machine={}

	local function ready()
		if destroyed then return false,"DESTROYED" end
		if busy then return false,"BUSY" end
		return true
	end

	-- All state mutations occur after a successful guard. Notifications run
	-- after commit, so notification failure never masquerades as rejection.
	local function change(target,payload)
		if not nameValid(target) or not states[target] then return false,"UNKNOWN_STATE" end
		if target==current then return false,"SAME_STATE" end
		local guard=states[current].Transitions[target]
		if not guard then return false,"TRANSITION_NOT_ALLOWED" end
		if guard~=true then
			local ok,result,detail=invoke(guard,context,current,target,payload)
			if not ok then return false,result,detail end
			if result~=true then return false,"GUARD_REJECTED" end
		end
		local previous=current
		current=target
		generation=table.freeze({})
		if onChanged then
			local ok,result,detail=invoke(onChanged,context,previous,target,payload)
			if not ok then return true,result,detail end
		end
		return true
	end

	function machine:GetState()
		if destroyed then return nil,"DESTROYED" end
		return current
	end
	function machine:Token()
		if destroyed then return nil,"DESTROYED" end
		return generation
	end
	function machine:IsCurrent(token)
		return not destroyed and token==generation
	end
	function machine:CanTransition(target)
		-- Graph-only query. It deliberately does not execute a user guard.
		return not destroyed and nameValid(target) and states[current].Transitions[target]~=nil
	end
	function machine:Transition(target,payload)
		local ok,err=ready()
		if not ok then return false,err end
		busy=true
		local success,code,detail=change(target,payload)
		busy=false
		return success,code,detail
	end
	function machine:TransitionIfCurrent(token,target,payload)
		local ok,err=ready()
		if not ok then return false,err end
		if token~=generation then return false,"STALE_TOKEN" end
		return machine:Transition(target,payload)
	end
	function machine:Step(dt)
		local ok,err=ready()
		if not ok then return false,err end
		if type(dt)~="number" or dt~=dt or dt<0 or dt==math.huge then return false,"INVALID_DT" end
		local update=states[current].Update
		if not update then return true end
		busy=true
		local ran,target,detail=invoke(update,context,dt,current)
		if not ran then busy=false; return false,target,detail end
		if target==nil then busy=false; return true end
		local success,code,extra=change(target,nil)
		busy=false
		return success,code,extra
	end
	function machine:Destroy()
		if destroyed then return true end
		if busy then return false,"BUSY" end
		destroyed=true
		current=nil
		generation=nil
		context=nil
		onChanged=nil
		states=nil
		return true
	end
	return table.freeze(machine)
end
return table.freeze(StateMachine)
