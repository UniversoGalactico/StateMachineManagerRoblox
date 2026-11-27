local count=0
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function suite(name,fn) fn(); count+=1; print("PASS "..name) end
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
	for _,guard in ipairs({function() error("bad") end,function() coroutine.yield() end,function() return 1 end}) do
		local m=new({States={A={Transitions={B=guard}},B={}}})
		local token=m:Token(); eq(m:Transition("B"),false); eq(m:GetState(),"A"); eq(m:Token(),token)
	end
end)
suite("postcommit errors and yield",function()
	for _,cb in ipairs({function() error("bad") end,function() coroutine.yield() end}) do
		local m=new({OnChanged=cb}); local token=m:Token(); local ok,err=m:Transition("B"); eq(ok,true); assert(err); eq(m:GetState(),"B"); eq(m:IsCurrent(token),false); eq(m:Transition("A"),true)
	end
end)
suite("reentrancy rejected in guard and notification",function()
	local m
	local function attack()
		local ok,err=m:Destroy(); eq(ok,false); eq(err,"BUSY")
		ok,err=m:Transition("B"); eq(ok,false); eq(err,"BUSY")
		ok,err=m:Step(0); eq(ok,false); eq(err,"BUSY")
		ok,err=m:TransitionIfCurrent(m:Token(),"B"); eq(ok,false); eq(err,"BUSY")
	end
	m=new({States={A={Transitions={B=function() attack(); eq(m:GetState(),"A"); return true end}},B={}},OnChanged=function() attack(); eq(m:GetState(),"B") end})
	local ok,err=m:Transition("B"); eq(ok,true); eq(err,nil); eq(m:Destroy(),true)
end)
suite("ABA and foreign tokens",function()
	local a,b=new(),new(); local old=a:Token()
	eq(a:IsCurrent(b:Token()),false); eq(a:Transition("B"),true); eq(a:Transition("A"),true)
	local ok,err=a:TransitionIfCurrent(old,"B"); eq(ok,false); eq(err,"STALE_TOKEN")
	eq(a:TransitionIfCurrent(a:Token(),"B"),true)
	eq(a:Destroy(),true); eq(a:IsCurrent(a:Token()),false); eq(a:Destroy(),true)
	eq(a:GetState(),nil); eq(a:Transition("A"),false); eq(a:Step(0),false)
end)
suite("step and guard pipeline",function()
	local ctx={n=0}; local m=new({Context=ctx,States={A={Update=function(c,dt,state) eq(state,"A"); c.n+=dt; if c.n>=2 then return "B" end end,Transitions={B=true}},B={}}})
	eq(m:Step(1),true); eq(m:GetState(),"A"); eq(m:Step(1),true); eq(m:GetState(),"B")
	for _,dt in ipairs({-1,math.huge,-math.huge,0/0,"bad",false}) do eq(m:Step(dt),false) end
	eq(m:Step(0),true)
end)
suite("update errors and invalid targets",function()
	for _,fn in ipairs({function() error("bad") end,function() coroutine.yield() end,function() return {} end,function() return "C" end}) do
		local m=new({States={A={Update=fn,Transitions={B=true}},B={}}})
		eq(m:Step(1),false); eq(m:GetState(),"A"); eq(m:Transition("B"),true)
	end
end)
suite("definition alias isolation",function()
	local def={A={Transitions={B=true}},B={}}
	local m=new({States=def}); def.A.Transitions.B=nil; def.A.Transitions.C=true; def.B=nil
	eq(m:Transition("B"),true); eq(m:GetState(),"B")
end)
suite("reject bad definitions",function()
	local cases={{Initial="X"},{States={A={Transitions={Z=true}}}},{States={A={Transitions={A=true}}}},{States={A={Transitions={B=false}},B={}}},{States={A={Update=false}}},{States={A={Typo=true}}},{OnChanged=false},{Typo=true},{States=setmetatable({A={}},{})}}
	for _,c in ipairs(cases) do eq(pcall(new,c),false) end
end)
suite("seeded graph and token model",function()
	local seed=37451
	local function random(n) seed=(seed*48271)%2147483647; return seed%n end
	for i=1,100 do
		local graph={}; for x=1,8 do graph[tostring(x)]={Transitions={}} end
		for x=1,8 do for y=1,8 do if x~=y and random(3)==0 then graph[tostring(x)].Transitions[tostring(y)]=true end end end
		local state="1"; local m=new({Initial=state,States=graph}); local token=m:Token()
		for _=1,1000 do
			local nextState=tostring(random(8)+1); local permitted=graph[state].Transitions[nextState]==true
			eq(m:CanTransition(nextState),permitted)
			eq(m:Transition(nextState),permitted)
			if permitted then eq(m:IsCurrent(token),false); state=nextState; token=m:Token() end
			eq(m:GetState(),state); eq(m:IsCurrent(token),true)
		end
		eq(m:Destroy(),true); eq(m:IsCurrent(token),false)
	end
end)
print("PASS "..count.." suites")
