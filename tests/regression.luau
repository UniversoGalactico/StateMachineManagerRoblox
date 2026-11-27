local count = 0
local function eq(a,b) assert(rawequal(a,b), tostring(a).." ~= "..tostring(b)) end
local function suite(name,fn)
	local ok,err=pcall(fn)
	if not ok then error("FAIL "..name..": "..tostring(err),0) end
	count+=1
	print("PASS "..name)
end
local function new(extra)
	local config={Initial="A",States={A={Transitions={B=true}},B={Transitions={A=true,C=true}},C={}}}
	for k,v in pairs(extra or {}) do config[k]=v end
	return StateMachine.new(config)
end
suite("graph and state",function()
	local m=new(); eq(m:GetState(),"A"); eq(m:CanTransition("B"),true); eq(m:CanTransition("C"),false)
	local ok,err=m:Transition("C"); eq(ok,false); eq(err,"TRANSITION_NOT_ALLOWED")
	eq(m:Transition("B"),true); eq(m:GetState(),"B")
	ok,err=m:Transition("B"); eq(ok,false); eq(err,"SAME_STATE")
	ok,err=m:Transition({}); eq(ok,false); eq(err,"UNKNOWN_STATE")
end)
suite("guard and payload",function()
	local ctx={allow=false}; local notifications=0
	local m=new({Context=ctx,States={A={Transitions={B=function(c,old,target,p) eq(c,ctx); eq(old,"A"); eq(target,"B"); eq(p,17); return c.allow end}},B={}},
	OnChanged=function(c,old,target,p) eq(c,ctx); eq(p,17); notifications+=1 end})
	local token=m:Token(); local ok,err=m:Transition("B",17); eq(ok,false); eq(err,"GUARD_REJECTED"); eq(m:Token(),token)
	ctx.allow=true; eq(m:Transition("B",17),true); eq(notifications,1)
end)
suite("guard errors and yield",function()
	for _,case in ipairs({{function() error("bad") end,"CALLBACK_ERROR"},{function() coroutine.yield() end,"CALLBACK_YIELDED"},{function() return 1 end,"GUARD_REJECTED"}}) do
		local m=new({States={A={Transitions={B=case[1]}},B={}}})
		local token=m:Token(); local ok,err=m:Transition("B"); eq(ok,false); eq(err,case[2]); eq(m:GetState(),"A"); eq(m:Token(),token)
	end
end)
suite("postcommit errors and yield",function()
	for _,cb in ipairs({function() error("bad") end,function() coroutine.yield() end}) do
		local m=new({OnChanged=cb}); local token=m:Token(); local ok,err,failures=m:Transition("B"); eq(ok,true); eq(err,"NOTIFICATION_FAILED"); eq(#failures,1); eq(failures[1].Stage,"OnChanged"); eq(m:GetState(),"B"); eq(m:IsCurrent(token),false); eq(m:Transition("A"),true)
	end
end)
suite("reentrancy rejected in all callback phases",function()
	local m
	local function attack()
		local ok,err=m:Destroy(); eq(ok,false); eq(err,"BUSY")
		for _,method in ipairs({"Transition","TransitionIfCurrent","Step","Send","SendIfCurrent"}) do
			ok,err=m[method](m,m:Token(),"B"); eq(ok,false); eq(err,"BUSY")
		end
	end
	m=new({States={A={Transitions={B=function() attack(); eq(m:GetState(),"A"); return true end},Exit=attack,Update=function() attack() end},B={Enter=attack}},OnChanged=function() attack(); eq(m:GetState(),"B") end})
	eq(m:Step(0),true); local ok,err=m:Transition("B"); eq(ok,true); eq(err,nil); eq(m:Destroy(),true)
end)
suite("ABA and foreign tokens",function()
	local a,b=new(),new(); local old=a:Token()
	eq(a:IsCurrent(b:Token()),false); eq(a:Transition("B"),true); eq(a:Transition("A"),true)
	local ok,err=a:TransitionIfCurrent(old,"B"); eq(ok,false); eq(err,"STALE_TOKEN")
	eq(a:TransitionIfCurrent(a:Token(),"B"),true)
	local forged=setmetatable({},{__eq=function() error("must not evaluate") end}); eq(a:IsCurrent(forged),false)
	eq(a:Destroy(),true); eq(a:IsCurrent(a:Token()),false); eq(a:Destroy(),true)
	eq(a:GetState(),nil); eq(a:Transition("A"),false); eq(a:Step(0),false); eq(a:Send("go"),false)
end)
suite("step and guard pipeline",function()
	local ctx={n=0}; local m=new({Context=ctx,States={A={Update=function(c,dt,state) eq(state,"A"); c.n+=dt; if c.n>=2 then return "B" end end,Transitions={B=true}},B={}}})
	eq(m:Step(1),true); eq(m:GetState(),"A"); eq(m:Step(1),true); eq(m:GetState(),"B")
	for _,dt in ipairs({-1,math.huge,-math.huge,0/0,"bad",false}) do eq(m:Step(dt),false) end
	eq(m:Step(0),true); eq(m:GetElapsed(),0)
end)
suite("update errors and invalid targets",function()
	for _,fn in ipairs({function() error("bad") end,function() coroutine.yield() end,function() return {} end,function() return "C" end}) do
		local m=new({States={A={Update=fn,Transitions={B=true}},B={}}})
		eq(m:Step(1),false); eq(m:GetState(),"A"); eq(m:GetElapsed(),1); eq(m:Transition("B"),true)
	end
end)
suite("definition alias isolation",function()
	local def={A={Transitions={B=true},Events={Go="B"},After={Seconds=5,Target="B"}},B={}}
	local m=new({States=def}); def.A.Transitions.B=nil; def.A.Transitions.C=true; def.A.Events.Go="C"; def.A.After.Seconds=0; def.B=nil
	eq(m:GetRemaining(),5); eq(m:CanSend("Go"),true); eq(m:Send("Go"),true); eq(m:GetState(),"B")
end)
suite("reject bad definitions",function()
	local cases={{Initial="X"},{States={A={Transitions={Z=true}}}},{States={A={Transitions={B=false}},B={}}},{States={A={Update=false}}},{States={A={Typo=true}}},{OnChanged=false},{Typo=true},{States=setmetatable({A={}},{})},
	{States={A={Events={Go="B"}},B={}}},{States={A={After={Seconds=1,Target="B"}},B={}}},{States={A={After={Seconds=0/0,Target="A"},Transitions={A=true}}}},{States={A={After={Seconds=math.huge,Target="A"},Transitions={A=true}}}},
	{States={A={After={Seconds=-1,Target="A"},Transitions={A=true}}}},{States={A={After={Seconds=1,Target="A",Typo=true},Transitions={A=true}}}},{States={A={Enter=false}}},{States={A={Exit={}}}},{States={A={Events=false}}},{States={A={Transitions=false}}},{States={A={After=false}}},
	{States={A={},["\255"]={}}},{States={A={},["bad\0name"]={}}}}
	for _,c in ipairs(cases) do eq(pcall(new,c),false) end
	eq(pcall(StateMachine.compile,{Initial="A",States={A={}},Context={}}),false)
end)
suite("compiled graph reused without aliasing",function()
	local cfg={Initial="A",States={A={Transitions={B=function(c) return c.allow end},Events={Go="B"}},B={}}}
	local g=StateMachine.compile(cfg); cfg.States.A.Transitions.B=nil; cfg.States.A.Events.Go=nil
	local ca,cb={allow=true},{allow=false}; local a=g:Create(ca); local b=g:Create(cb)
	eq(a:Send("Go"),true); eq(b:Send("Go"),false); eq(a:GetState(),"B"); eq(b:GetState(),"A")
	a:Destroy(); cb.allow=true; eq(b:Send("Go"),true); eq(g:Create(ca):GetState(),"A")
	eq(pcall(function() g.Create=nil end),false)
end)
suite("events and stale event dispatch",function()
	local m=new({States={A={Transitions={B=true},Events={Go="B"}},B={Transitions={A=true},Events={Back="A"}}}})
	local t=m:Token(); eq(m:CanSend("Go"),true); eq(m:SendIfCurrent(t,"Go"),true)
	local ok,err=m:SendIfCurrent(t,"Back"); eq(ok,false); eq(err,"STALE_TOKEN")
	eq(m:Send("Back"),true); ok,err=m:Send("Back"); eq(ok,false); eq(err,"UNKNOWN_EVENT")
	eq(m:IsCurrent(t),false); eq(m:CanSend({}),false)
end)
suite("sorted immutable introspection",function()
	local m=new({States={A={Transitions={C=true,B=true,A=true},Events={z="A",a="C"}},B={},C={}}})
	local transitions=m:GetTransitions(); eq(table.concat(transitions,","),"A,B,C"); eq(pcall(function() transitions[1]="Z" end),false)
	local events=m:GetEvents(); eq(table.concat(events,","),"a,z"); eq(pcall(function() events[1]="x" end),false)
	m:Destroy(); eq(m:GetTransitions(),nil); eq(m:GetEvents(),nil)
end)
suite("explicit self transition resets time and token",function()
	local m=new({States={A={Transitions={A=true},Events={Restart="A"},After={Seconds=4,Target="A"}}}})
	local t=m:Token(); eq(m:Step(2),true); eq(m:GetElapsed(),2); eq(m:Send("Restart"),true); eq(m:GetElapsed(),0); eq(m:IsCurrent(t),false)
	t=m:Token(); eq(m:Step(4),true); eq(m:GetElapsed(),0); eq(m:IsCurrent(t),false); eq(m:GetState(),"A")
end)
suite("timed transition and overshoot",function()
	local m=new({States={A={Transitions={B=true},After={Seconds=2,Target="B"}},B={Transitions={C=true},After={Seconds=1,Target="C"}},C={}}})
	eq(m:GetRemaining(),2); eq(m:Step(1.5),true); eq(m:GetRemaining(),0.5); eq(m:GetState(),"A")
	eq(m:Step(10),true); eq(m:GetState(),"B"); eq(m:GetElapsed(),0); eq(m:GetRemaining(),1)
	eq(m:Step(1),true); eq(m:GetState(),"C"); eq(m:GetRemaining(),nil)
end)
suite("zero timer only one transition per step",function()
	local m=new({States={A={Transitions={B=true},After={Seconds=0,Target="B"}},B={Transitions={A=true},After={Seconds=0,Target="A"}}}})
	eq(m:GetState(),"A"); eq(m:Step(0),true); eq(m:GetState(),"B"); eq(m:Step(0),true); eq(m:GetState(),"A")
end)
suite("timer guard can recover on next step",function()
	local c={allow=false,n=0}; local m=new({Context=c,States={A={Transitions={B=function(ctx) return ctx.allow end},After={Seconds=1,Target="B"},Update=function(ctx) ctx.n+=1 end},B={}}})
	local ok,err=m:Step(1); eq(ok,false); eq(err,"GUARD_REJECTED"); eq(m:GetRemaining(),0); eq(c.n,1); eq(m:GetState(),"A")
	c.allow=true; eq(m:Step(0),true); eq(c.n,2); eq(m:GetState(),"B")
end)
suite("update target has priority over timer",function()
	local m=new({States={A={Transitions={B=true,C=true},After={Seconds=1,Target="B"},Update=function() return "C" end},B={},C={}}})
	eq(m:Step(1),true); eq(m:GetState(),"C")
end)
suite("notification ordering and error aggregation",function()
	local order={}; local m
	local function mark(stage,shouldError)
		return function(ctx,old,new,payload)
			eq(m:GetState(),"B"); eq(m:GetElapsed(),0); eq(old,"A"); eq(new,"B"); eq(payload,5)
			table.insert(order,stage); if shouldError then error(stage) end
		end
	end
	m=new({States={A={Transitions={B=true},Exit=mark("exit",true)},B={Enter=mark("enter",true)}},OnChanged=mark("changed",false)})
	eq(#order,0); m:Step(3); local ok,err,fail=m:Transition("B",5)
	eq(ok,true); eq(err,"NOTIFICATION_FAILED"); eq(#fail,2); eq(fail[1].Stage,"Exit"); eq(fail[2].Stage,"Enter"); eq(table.concat(order,","),"exit,enter,changed")
	m:Destroy(); eq(#order,3)
end)
suite("numerical time bounds and compensated steps",function()
	local m=new(); eq(m:Step(2^53),true); eq(m:Step(1),true); eq(m:Step(1),true); eq(m:GetElapsed(),2^53+2)
	local q=new(); eq(q:Step(1e308),true); local ok,err=q:Step(1e308); eq(ok,false); eq(err,"TIME_OVERFLOW"); eq(q:GetElapsed(),1e308)
	local r=new(); for _=1,10 do eq(r:Step(0.1),true) end; eq(r:GetElapsed(),1)
end)
suite("destroy drops context and definition references",function()
	local m=new({Context={n=1}}); local token=m:Token(); eq(m:Destroy(),true)
	for _,method in ipairs({"GetState","GetElapsed","GetRemaining","GetEvents","GetTransitions","Token"}) do local v,e=m[method](m); eq(v,nil); eq(e,"DESTROYED") end
	eq(m:IsCurrent(token),false); eq(m:CanSend("x"),false); eq(m:CanTransition("B"),false)
end)
suite("seeded graph and token model",function()
	local seed=37451
	local function random(n) seed=(seed*48271)%2147483647; return seed%n end
	for i=1,100 do
		local graph={}; for x=1,8 do graph[tostring(x)]={Transitions={}} end
		for x=1,8 do for y=1,8 do if random(3)==0 then graph[tostring(x)].Transitions[tostring(y)]=true end end end
		local state="1"; local m=new({Initial=state,States=graph}); local token=m:Token()
		for _=1,1000 do
			local nextState=tostring(random(8)+1); local permitted=graph[state].Transitions[nextState]==true
			eq(m:CanTransition(nextState),permitted); eq(m:Transition(nextState),permitted)
			if permitted then eq(m:IsCurrent(token),false); state=nextState; token=m:Token() end
			eq(m:GetState(),state); eq(m:IsCurrent(token),true)
		end
		eq(m:Destroy(),true); eq(m:IsCurrent(token),false)
	end
end)
suite("seeded event timer and guarded state model",function()
	local seed=20261127
	local function random(n) seed=(seed*48271)%2147483647; return seed%n end
	for iteration=1,100 do
		local config={Initial="1",States={}}
		local model={}
		for i=1,5 do
			local name=tostring(i); local target=tostring(i%5+1); local selfTarget=name
			local delay=random(16)/4
			config.States[name]={Transitions={[target]=function(c) return c.allow end,[selfTarget]=true},Events={next=target,restart=selfTarget},After={Seconds=delay,Target=target}}
			model[name]={target=target,delay=delay}
		end
		local graph=StateMachine.compile(config); local ctx={allow=true}; local m=graph:Create(ctx)
		local state,elapsed,token="1",0,m:Token()
		for _=1,1000 do
			local op=random(5); ctx.allow=random(2)==1
			local before=state; local transition=false; local expected=true; local expectedError=nil; local ok,err
			if op==0 then
				local dt=random(12)/4; elapsed+=dt
				if elapsed>=model[state].delay then
					if ctx.allow then state=model[state].target; transition=true else expected=false; expectedError="GUARD_REJECTED" end
				end
				ok,err=m:Step(dt)
			elseif op==1 then
				if ctx.allow then state=model[state].target; transition=true else expected=false; expectedError="GUARD_REJECTED" end
				ok,err=m:SendIfCurrent(token,"next")
			elseif op==2 then transition=true; ok,err=m:Send("restart")
			elseif op==3 then expected=false; expectedError="STALE_TOKEN"; ok,err=m:SendIfCurrent({},"restart")
			else expected=false; expectedError="UNKNOWN_EVENT"; ok,err=m:Send("unknown") end
			eq(ok,expected); eq(err,expectedError); eq(m:GetState(),state)
			if transition then eq(m:IsCurrent(token),false); token=m:Token(); elapsed=0 else eq(m:IsCurrent(token),true); eq(state,before) end
			eq(m:GetElapsed(),elapsed); eq(m:GetRemaining(),math.max(0,model[state].delay-elapsed))
		end
		m:Destroy()
	end
end)
suite("zero dt rounding witness is stable",function()
	local m=new(); eq(m:Step(0.000009),true); eq(m:Step(0.00002),true)
	local before=m:GetElapsed(); eq(m:Step(0),true); eq(m:GetElapsed(),before)
end)
suite("update payload and timer payload isolation",function()
	local payload={kind="target"}; local seen=0
	local m=new({States={A={Transitions={B=function(c,o,n,p) eq(p,payload); return true end},Update=function() return "B",payload end},B={Enter=function(c,o,n,p) eq(p,payload); seen+=1 end}}})
	eq(m:Step(0),true); eq(m:GetState(),"B"); eq(seen,1)
	local q=new({States={A={Transitions={B=function(c,o,n,p) eq(p,nil); return true end},After={Seconds=0,Target="B"},Update=function() return nil,payload end},B={}}})
	eq(q:Step(0),true); eq(q:GetState(),"B")
end)
print("PASS "..count.." suites")
