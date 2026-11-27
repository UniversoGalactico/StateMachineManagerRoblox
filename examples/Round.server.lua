-- Example round flow driven by one existing controller loop.
local RunService=game:GetService("RunService")
local StateMachine=require(script.Parent.StateMachine)
local context={PlayersReady=0}
local round=StateMachine.new({
	Initial="Waiting", Context=context,
	States={
		Waiting={Transitions={Countdown=function(c) return c.PlayersReady>=2 end},Events={Ready="Countdown"}},
		Countdown={Transitions={Waiting=true,Playing=function(c) return c.PlayersReady>=2 end},
			Events={Cancel="Waiting"},After={Seconds=10,Target="Playing"}},
		Playing={Transitions={Results=true},Events={Finished="Results"}},
		Results={Transitions={Waiting=true},After={Seconds=5,Target="Waiting"}},
	},
	OnChanged=function(c,old,new) print("Round",old,"->",new) end,
})
local connection=RunService.Heartbeat:Connect(function(dt)
	-- The owner should handle expected guard rejection without logging every frame.
	local ok,code=round:Step(dt)
	if code and code~="GUARD_REJECTED" then warn(ok,code) end
end)
-- Example controller updates, not an implementation of matchmaking.
context.PlayersReady=2
round:Send("Ready")
-- In asynchronous work, capture a token and use round:SendIfCurrent(token,"Finished").
script.Destroying:Once(function() connection:Disconnect(); round:Destroy() end)
