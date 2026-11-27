#!/usr/bin/env python3
"""Finite numerical differential checks using an external, pinned LuauProof 3.20."""
import argparse, hashlib, json, random, struct, subprocess, sys, tempfile, time
from fractions import Fraction
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--luauproof',type=Path,required=True)
p.add_argument('--source',type=Path,default=Path('StateMachineManagerRoblox.lua'))
p.add_argument('--seed',type=int,default=32031)
p.add_argument('--out',type=Path,required=True)
a=p.parse_args(); started=time.monotonic(); root=a.luauproof.resolve()
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
pins={'numeric_fuzz320.py':'5d4cf91db579d2097cac2d13b9a77bef0bbad54878a47ad493a5d502d6f3e4b0','binary64_320.py':'8995a1949fcc910986bcfe38a9b9c406410db3c25929c45233f1a250a6fe8253','runtime/linux/luau':'7741b96bd8fadb340965b7468dc4a2be8fe41247b8219bd8d4a7e80f16b40625','vm_binary64_320.py':'ba264eb5b102209ab0dbacc7c189a8fcd1536f08ed0805d1f88b4647be370af6'}
for path,h in pins.items(): assert sha(root/path)==h, path
sys.path.insert(0,str(root))
from numeric_fuzz320 import generate,expr,eval_ast
from vm_binary64_320 import pairs
from binary64_320 import parts, arithmetic, encode, INF, SIGN
rng=random.Random(a.seed); pool=pairs(a.seed,10000); selected=rng.sample(pool,128); trees=generate(a.seed,128)
def value(b):
 s,k,x=parts(b)
 return (-x if s else x) if k in ('finite','zero') else None
def valid(b):
 v=value(b); return v is not None and v>=0
def bits(b):return f'{b&0xffffffff},{b>>32}'
def bl(x):return str(bool(x)).lower()
def lit(s):return '"'+''.join('\\%03d'%b for b in s)+'"'
body=[r'''
local counts,bad={},{}
local function check(group,ok,label)
 counts[group]=(counts[group] or 0)+1
 if not ok then bad[group]=(bad[group] or 0)+1; if bad[group]<=12 then print("DIFF",group,label) end end
end
local function frombits(lo,hi) return (string.unpack("<d",string.pack("<I4I4",lo,hi))) end
local function matches(v,e)
 if e~=e then return v~=v end
 if e==0 then return v==0 end
 return string.pack("<d",v)==string.pack("<d",e)
end
local plain=StateMachine.compile({Initial="A",States={A={Transitions={A=true}}}})
local m=plain:Create()
local funcs={}
''']
for i,t in enumerate(trees):body.append(f'funcs[{i+1}]=function(a,b) return {expr(t)} end')
body.append(r'''
local function checkdt(i,v,e,valid)
 m:Transition("A")
 local token=m:Token()
 local ok,code=m:Step(v)
 check("step_admission",ok==valid,i)
 check("step_error",code==(if valid then nil else "INVALID_DT"),i)
 check("step_elapsed",matches(m:GetElapsed(),if valid then e else 0),i)
 check("step_token",m:IsCurrent(token),i)
end
local function numeric(i,f,al,ah,bl,bh,el,eh,valid)
 local v=funcs[f](frombits(al,ah),frombits(bl,bh)); local e=frombits(el,eh)
 check("oracle",matches(v,e),i)
 checkdt(i,v,e,valid)
end
local function timer(i,al,ah,bl,bh,tl,th,suml,sumh,overflow,firstDue,secondDue)
 local a,b,t=frombits(al,ah),frombits(bl,bh),frombits(tl,th)
 local expected=frombits(suml,sumh)
 local q=StateMachine.new({Initial="A",States={A={Transitions={B=true},After={Seconds=t,Target="B"}},B={}}})
 local token=q:Token(); local ok,err=q:Step(a)
 check("timer_first_success",ok,i)
 check("timer_first_state",q:GetState()==(if firstDue then "B" else "A"),i)
 check("timer_first_token",q:IsCurrent(token)==not firstDue,i)
 if firstDue then return end
 ok,err=q:Step(b)
 check("timer_second_success",ok==not overflow,i)
 check("timer_second_state",q:GetState()==(if secondDue then "B" else "A"),i)
 check("timer_second_token",q:IsCurrent(token)==not secondDue,i)
 check("timer_second_elapsed",matches(q:GetElapsed(),if secondDue then 0 elseif overflow then a else expected),i)
 if not secondDue then
  check("timer_remaining_nonnegative",q:GetRemaining()>=0,i)
 end
end
local function duration(i,lo,hi,valid)
 local d=frombits(lo,hi)
 local ok=pcall(StateMachine.new,{Initial="A",States={A={Transitions={A=true},After={Seconds=d,Target="A"}}}})
 check("duration_admission",ok==valid,i)
end
local function name(i,s,valid)
 local ok=pcall(StateMachine.new,{Initial=s,States={[s]={}}})
 check("name_admission",ok==valid,i)
 if ok then local q=StateMachine.new({Initial=s,States={[s]={}}}); check("name_roundtrip",q:GetState()==s,i) end
end
local function longsum(i,values,lo,hi,ulpLo,ulpHi)
 local q=plain:Create(); local previous=0
 for _,v in ipairs(values) do
  local ok=q:Step(v); check("sum_admission",ok,i)
  local nextValue=q:GetElapsed();check("sum_monotonic",nextValue>=previous,i);previous=nextValue
 end
 local expected=frombits(lo,hi);local tolerance=frombits(ulpLo,ulpHi)
 check("sum_two_ulp",math.abs(q:GetElapsed()-expected)<=tolerance,i)
 local before=q:GetElapsed();q:Step(0);check("zero_step_invariance",q:GetElapsed()==before,i)
end
''')
for i,t in enumerate(trees):
 for j,(x,y) in enumerate(selected):
  b=eval_ast(t,x,y);body.append(f'numeric({i*128+j},{i+1},{bits(x)},{bits(y)},{bits(b)},{bl(valid(b))})')
for i,(x,y) in enumerate(pool[:4000]):
 body.append(f'duration({i},{bits(x)},{bl(valid(x))})')
# Positive finite operands, thresholds deliberately straddle the rounded two-step sum.
numtimers=0
for i,(x,y) in enumerate(pool):
 if numtimers>=8000:break
 x&=~SIGN;y&=~SIGN
 if not valid(x) or not valid(y):continue
 total=arithmetic('add',x,y); overflow=total==INF
 choices=[0,x,max(0,x-1),min(INF-1,x+1),INF-1]
 if not overflow: choices += [max(0,total-1),total,min(INF-1,total+1)]
 threshold=rng.choice(choices)
 first=value(x)>=value(threshold)
 second=not first and not overflow and value(total)>=value(threshold)
 body.append(f'timer({i},{bits(x)},{bits(y)},{bits(threshold)},{bits(total)},{bl(overflow)},{bl(first)},{bl(second)})');numtimers+=1
for i in range(3000):
 s=bytes(rng.randrange(256) for _ in range(rng.randrange(0,150))) if i%3 else (chr(rng.choice([rng.randrange(0xd800),rng.randrange(0xe000,0x110000)]))*rng.randrange(1,40)).encode()
 try:s.decode('utf-8'); good=0<len(s)<=128 and not any(b<32 or b==127 for b in s)
 except UnicodeDecodeError:good=False
 body.append(f'name({i},{lit(s)},{bl(good)})')
# Independent exact rational accumulation, with a documented two-ULP tolerance.
for i in range(1500):
 n=rng.randrange(2,50); seq=[]
 for j in range(n):
  if i%4==0: v=Fraction(rng.randrange(1,10),10**rng.randrange(1,8))
  elif i%4==1: v=Fraction(rng.randrange(1,1024),1<<rng.randrange(0,54))
  elif i%4==2: v=Fraction(rng.randrange(1,1024))*(Fraction(2)**rng.randrange(-800,801))
  else: v=Fraction(1<<53) if j==0 else Fraction(rng.randrange(0,4))
  seq.append(encode(v))
 exact=sum((value(b) for b in seq),Fraction(0)); expected=encode(exact)
 tolerance=encode(2*abs(value(expected+1)-value(expected))) if expected<INF-1 else 0
 body.append('longsum(%d,{%s},%s,%s)'%(i,','.join('frombits(%s)'%bits(b) for b in seq),bits(expected),bits(tolerance)))
body.append('for group,n in pairs(counts) do print("COUNT",group,n,bad[group] or 0) end')
source='local StateMachine=(function()\n'+a.source.read_text()+'\nend)()\n'+'\n'.join(body)
runs=[]
with tempfile.TemporaryDirectory() as td:
 path=Path(td)/'audit.luau';path.write_text(source)
 for opt in range(3):
  run=subprocess.run([str(root/'runtime/linux/luau'),f'-O{opt}',str(path)],capture_output=True,text=True,timeout=90)
  if run.returncode:raise RuntimeError(run.stderr+run.stdout[-2000:])
  counts={};diff=[]
  for line in run.stdout.splitlines():
   row=line.split('\t')
   if row[0]=='COUNT':counts[row[1]]={'checks':int(row[2]),'differences':int(row[3])}
   elif row[0]=='DIFF':diff.append(row[1:])
  assert counts.get('oracle',{}).get('checks')==128*128 and counts.get('timer_first_success',{}).get('checks')==numtimers and counts.get('sum_two_ulp',{}).get('checks')==1500
  runs.append({'optimization':opt,'counts':counts,'witnesses':diff});print(opt,'checks',sum(v['checks'] for v in counts.values()),'differences',sum(v['differences'] for v in counts.values()),diff[:12],flush=True)
report={'source_sha256':sha(a.source),'campaign_sha256':sha(Path(__file__)),'tool_pins':pins,'seed':a.seed,'runs':runs,'elapsed_seconds':time.monotonic()-started,'scope':'finite numerical, name validation and timer checks, rounded binary64 time with two-ULP tolerance for longer sums; not formal verification or Roblox Studio tests'}
a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(report,indent=2)+'\n')
sys.exit(int(any(v['differences'] for run in runs for v in run['counts'].values())))
