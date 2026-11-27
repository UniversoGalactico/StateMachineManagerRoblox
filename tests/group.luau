suite("group insertion order, duplicate and dt validation",function()
	local g=StateMachineGroup.new(); local seen={}
	local a={Step=function(self,dt) table.insert(seen,"a"); eq(dt,2); return true end}
	local b={Step=function() table.insert(seen,"b"); return true end}
	eq(g:Add(a),true); eq(g:Add(b),true); eq(g:Add(a),false); eq(g:Count(),2); eq(g:Has(a),true)
	eq(g:Step(-1),false); eq(#seen,0); local ok,r=g:Step(2); eq(ok,true); eq(r.Attempted,2); eq(r.Succeeded,2); eq(table.concat(seen,","),"a,b")
	eq(g:Remove(a),true); eq(g:Remove(a),false); eq(g:Has(a),false); eq(g:Count(),1)
	eq(g:Destroy(),true); eq(g:Destroy(),true); eq(g:Count(),0); eq(g:Add(a),false); eq(g:Step(2),false)
end)
suite("group removal and re-add during iteration",function()
	local g=StateMachineGroup.new(); local seen={}; local a,b,c
	b={Step=function() table.insert(seen,"b"); return true end}
	c={Step=function() table.insert(seen,"c"); return true end}
	local once=true
	a={Step=function()
		table.insert(seen,"a")
		if once then once=false; eq(g:Remove(b),true); eq(g:Add(b),true); eq(g:Add(c),true) end
		local ok,err=g:Step(1); eq(ok,false); eq(err,"BUSY"); eq(g:Destroy(),false)
		return true
	end}
	g:Add(a); g:Add(b)
	local ok,r=g:Step(1); eq(ok,true); eq(r.Attempted,1); eq(table.concat(seen,","),"a")
	ok,r=g:Step(1); eq(ok,true); eq(r.Attempted,3); eq(table.concat(seen,","),"a,a,b,c")
end)
suite("group faults are isolated and reported",function()
	local g=StateMachineGroup.new(); local n=0
	local cases={function() error("broken") end,function() coroutine.yield() end,function() return false,"NO" end,function() return true,"WARNING" end,function() return nil end,function() n+=1; return true end}
	for _,fn in ipairs(cases) do eq(g:Add({Step=fn}),true) end
	local ok,r=g:Step(1); eq(ok,true); eq(r.Attempted,6); eq(r.Succeeded,2); eq(r.Failed,4); eq(r.Warnings,1); eq(#r.Issues,5); eq(n,1)
	for i,code in ipairs({"STEP_ERROR","STEP_YIELDED","NO","WARNING","INVALID_STEP_RESULT"}) do eq(r.Issues[i].Code,code) end
end)
suite("group destroyed member removed, membership not ownership",function()
	local g=StateMachineGroup.new(); local a,b=new(),new(); g:Add(a); g:Add(b); a:Destroy()
	local ok,r=g:Step(0); eq(ok,true); eq(r.RemovedDestroyed,1); eq(g:Has(a),false); eq(g:Has(b),true); eq(g:Count(),1)
	g:Destroy(); eq(b:GetState(),"A"); eq(b:Transition("B"),true)
end)
suite("group ABA removal cannot remove replacement",function()
	local g=StateMachineGroup.new(); local m; local first=true
	m={Step=function()
		if first then first=false; eq(g:Remove(m),true); eq(g:Add(m),true); return false,"DESTROYED" end
		return true
	end}
	g:Add(m); local ok,r=g:Step(0); eq(ok,true); eq(r.RemovedDestroyed,0); eq(g:Has(m),true)
	ok,r=g:Step(0); eq(ok,true); eq(r.Succeeded,1)
end)
suite("group mass churn preserves insertion order",function()
	local g=StateMachineGroup.new(); local seen={}; local entries={}
	for i=1,500 do local member={Step=function() table.insert(seen,i); return true end}; entries[i]=member; g:Add(member) end
	for i=1,400 do eq(g:Remove(entries[i]),true) end
	for i=1,100 do eq(g:Add(entries[i]),true) end
	local ok,r=g:Step(0); eq(ok,true); eq(r.Attempted,200); eq(g:Count(),200)
	for i=1,100 do eq(seen[i],400+i); eq(seen[100+i],i) end
end)
suite("group rejects malformed adapters and captures registered method",function()
	local g=StateMachineGroup.new(); eq(g:Add(nil),false); eq(g:Add({}),false); eq(g:Add(setmetatable({Step=function() end},{})),false)
	local m={Step=function() return true end}; eq(g:Add(m),true); m.Step=function() error("replacement") end
	local ok,r=g:Step(0); eq(ok,true); eq(r.Succeeded,1)
end)
suite("seeded membership model under callback churn",function()
	local seed=97231
	local function random(n) seed=(seed*48271)%2147483647; return seed%n end
	local members, actions, observed, order, active, generations = {}, {}, {}, {}, {}, {}
	local group=StateMachineGroup.new()
	local function modelAdd(i)
		if active[i] then return false end
		generations[i]=(generations[i] or 0)+1
		active[i]=generations[i]; table.insert(order,{Id=i,Generation=active[i]}); return true
	end
	local function modelRemove(i)
		if not active[i] then return false end
		active[i]=nil; return true
	end
	for i=1,32 do
		members[i]={Step=function()
			table.insert(observed,i)
			local a=actions[i]
			if a.Remove then group:Remove(members[a.Remove]) end
			if a.Add then group:Add(members[a.Add]) end
			if a.Destroyed then return false,"DESTROYED" end
			if a.Fail then return false,"TEST_FAILURE" end
			if a.Warning then return true,"TEST_WARNING" end
			return true
		end}
	end
	for tick=1,2000 do
		for i=1,32 do
			actions[i]={Remove=if random(3)==0 then random(32)+1 else nil,Add=if random(3)==0 then random(32)+1 else nil,Destroyed=random(11)==0,Fail=random(7)==0,Warning=random(5)==0}
		end
		for _=1,4 do
			local i=random(32)+1
			if random(2)==0 then eq(group:Add(members[i]),modelAdd(i)) else eq(group:Remove(members[i]),modelRemove(i)) end
		end
		local expected={}; local failed,warnings,removed=0,0,0
		-- Separate reference representation with explicit membership generations.
		local snapshot=table.clone(order)
		for _,r in ipairs(snapshot) do
			local i=r.Id
			if active[i]~=r.Generation then continue end
			table.insert(expected,i)
			local a=actions[i]
			if a.Remove then modelRemove(a.Remove) end
			if a.Add then modelAdd(a.Add) end
			if a.Destroyed then
				failed+=1
				if active[i]==r.Generation then modelRemove(i); removed+=1 end
			elseif a.Fail then failed+=1
			elseif a.Warning then warnings+=1 end
		end
		observed={}; local ok,result=group:Step(0); eq(ok,true)
		eq(table.concat(observed,","),table.concat(expected,",")); eq(result.Attempted,#expected); eq(result.Failed,failed); eq(result.Warnings,warnings); eq(result.RemovedDestroyed,removed)
		local n=0
		for i=1,32 do eq(group:Has(members[i]),active[i]~=nil); if active[i] then n+=1 end end
		eq(group:Count(),n)
		local fresh={}; for _,r in ipairs(order) do if active[r.Id]==r.Generation then table.insert(fresh,r) end end; order=fresh
	end
end)
