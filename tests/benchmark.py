"""Local CLI microbenchmark, not a Roblox frame-rate or capacity guarantee."""
import argparse,json,pathlib,subprocess,tempfile,hashlib,platform
p=argparse.ArgumentParser();p.add_argument('--luau',required=True);p.add_argument('--out',type=pathlib.Path);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
core=(root/'StateMachineManagerRoblox.lua').read_text();group=(root/'StateMachineGroup.lua').read_text()
bench=r'''
local N=3000
local FRAMES=300
local config={Initial="Idle",States={
 Idle={Transitions={Move=true},Events={start="Move"},After={Seconds=0.5,Target="Move"}},
 Move={Transitions={Idle=true},Events={stop="Idle"},After={Seconds=1,Target="Idle"}},
}}
local graph=StateMachine.compile(config)
local function run(label,fn,units)
 local t=os.clock();local result=fn(); local elapsed=os.clock()-t
 print("BENCH",label,elapsed,units,result or 0)
end
local function create(compileEach)
 local machines={}
 for i=1,N do machines[i]=if compileEach then StateMachine.new(config) else graph:Create() end
 assert(#machines==N)
 for _,m in ipairs(machines) do m:Destroy() end
 return #machines
end
local machines={}
for i=1,N do machines[i]=graph:Create() end
local g=StateMachineGroup.new()
for _,m in ipairs(machines) do assert(g:Add(m)) end
local function direct()
 for i=1,FRAMES do for _,m in ipairs(machines) do assert(m:Step(1/60)) end end
 return #machines
end
local function grouped()
 for i=1,FRAMES do local ok,r=g:Step(1/60); assert(ok and r.Attempted==N and r.Failed==0) end
 return g:Count()
end
-- Warm both paths; repeated measurements with alternating order.
create(true);create(false);direct();grouped()
for trial=1,5 do
 if trial%2==1 then run("new",function()return create(true)end,N); run("compiled",function()return create(false)end,N)
 else run("compiled",function()return create(false)end,N); run("new",function()return create(true)end,N) end
 if trial%2==1 then run("direct_step",direct,N*FRAMES);run("group_step",grouped,N*FRAMES)
 else run("group_step",grouped,N*FRAMES);run("direct_step",direct,N*FRAMES) end
end
for _,m in ipairs(machines) do m:Destroy() end
assert(g:Step(0));assert(g:Count()==0)
'''
with tempfile.TemporaryDirectory() as tmp:
 path=pathlib.Path(tmp)/'bench.luau'
 path.write_text('local StateMachine=(function()\n'+core+'\nend)()\nlocal StateMachineGroup=(function()\n'+group+'\nend)()\n'+bench)
 result=subprocess.run([a.luau,'-O2',str(path)],capture_output=True,text=True,check=True,timeout=120)
rows=[]
for line in result.stdout.splitlines():
 row=line.split('\t')
 if row[0]=='BENCH':rows.append({'operation':row[1],'seconds':float(row[2]),'units':int(row[3]),'verified_result':int(row[4])})
assert len(rows)==20
report={'scope':'local CLI O2 microbenchmark, includes machine construction/destruction and timed-state steps; not Roblox Studio or production capacity','platform':platform.platform(),'module_sha256':hashlib.sha256(core.encode()).hexdigest(),'group_sha256':hashlib.sha256(group.encode()).hexdigest(),'vm_sha256':hashlib.sha256(pathlib.Path(a.luau).read_bytes()).hexdigest(),'rows':rows}
import statistics
for key in ('new','compiled','direct_step','group_step'):
 values=[r['seconds'] for r in rows if r['operation']==key]; print(key,'median',statistics.median(values),'seconds', 'trials',values)
if a.out:a.out.write_text(json.dumps(report,indent=2)+'\n')
