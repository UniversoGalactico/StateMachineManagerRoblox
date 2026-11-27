"""Deliberately break selected contracts and verify regression tests notice them."""
import argparse, hashlib, json, pathlib, subprocess, tempfile, time
p=argparse.ArgumentParser(); p.add_argument('--luau',required=True);p.add_argument('--out',type=pathlib.Path);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
core=(root/'StateMachineManagerRoblox.lua').read_text();group=(root/'StateMachineGroup.lua').read_text()
tests=(root/'tests/regression.luau').read_text().replace('print("PASS "..count.." suites")','')+'\n'+(root/'tests/group.luau').read_text()
mutants=[
 ('skip_guard','core','if result ~= true then return false, "GUARD_REJECTED", nil end','if false then return false, "GUARD_REJECTED", nil end'),
 ('keep_old_generation','core','generation = table.freeze({})\n\t\telapsed, correction = 0, 0','generation = generation\n\t\telapsed, correction = 0, 0'),
 ('keep_elapsed_on_commit','core','elapsed, correction = 0, 0\n\t\tlocal failures','elapsed, correction = elapsed, correction\n\t\tlocal failures'),
 ('report_committed_as_rejected','core','return true, "NOTIFICATION_FAILED", failures','return false, "NOTIFICATION_FAILED", failures'),
 ('skip_notification','core','notify("Enter", state().Enter)','-- missing enter notification'),
 ('allow_reentry','core','if busy then return false, "BUSY" end\n\t\treturn true, nil','if false then return false, "BUSY" end\n\t\treturn true, nil'),
 ('accept_unknown_event_target','core','and edges[target] ~= nil, "INVALID_EVENT"','and true, "INVALID_EVENT"'),
 ('timer_overrides_update','core','if target == nil and timer ~= nil and elapsed >= timer.Seconds','if timer ~= nil and elapsed >= timer.Seconds'),
 ('consume_rounding_debt_on_zero','core','if dt > 0 then','if dt >= 0 then'),
 ('drop_update_payload','core','target, payload = result, detail','target, payload = result, nil'),
 ('ignore_foreign_event_token','core','if not rawequal(token, generation) then return false, "STALE_TOKEN", nil end\n\t\tlocal target, eventErr','if false then return false, "STALE_TOKEN", nil end\n\t\tlocal target, eventErr'),
 ('group_count_duplicate','group','if records[member] then return false, "ALREADY_ADDED" end','if false then return false, "ALREADY_ADDED" end'),
 ('group_aba_autoremoval','group','if not ok and code == "DESTROYED" and remove(record) then','if not ok and code == "DESTROYED" and records[member] and remove(records[member]) then'),
 ('group_ignore_yield','group','return false, "STEP_YIELDED", nil','return false, "STEP_ERROR", nil'),
 ('group_false_success','group','if ok then summary.Succeeded += 1 else summary.Failed += 1 end','summary.Succeeded += 1'),
]
def run(c,g):
 with tempfile.TemporaryDirectory() as tmp:
  path=pathlib.Path(tmp)/'test.luau';path.write_text('local StateMachine=(function()\n'+c+'\nend)()\nlocal StateMachineGroup=(function()\n'+g+'\nend)()\n'+tests)
  return subprocess.run([a.luau,'-O2',str(path)],capture_output=True,text=True,timeout=8)
base=run(core,group);assert base.returncode==0,base.stderr
rows=[]
for name,kind,old,new in mutants:
 target=core if kind=='core' else group
 assert target.count(old)==1,(name,target.count(old))
 changed=target.replace(old,new,1)
 try:
  result=run(changed,group) if kind=='core' else run(core,changed)
  # Count only a test failure (not a compiler failure) as detected.
  line=next((x for x in result.stderr.splitlines() if 'FAIL ' in x),'')
  detected=result.returncode!=0 and bool(line)
  detail=line.split('FAIL ',1)[-1] if detected else result.stderr[:200]
 except subprocess.TimeoutExpired: detected=False;detail='TIMEOUT_INCONCLUSIVE'
 rows.append({'mutant':name,'detected':detected,'detail':detail});print(name,detected,detail)
report={'scope':'selected non-equivalent deliberate semantic mutations; not a universal mutation score','module_sha256':hashlib.sha256(core.encode()).hexdigest(),'group_sha256':hashlib.sha256(group.encode()).hexdigest(),'rows':rows}
if a.out:a.out.write_text(json.dumps(report,indent=2)+'\n')
assert all(x['detected'] for x in rows),'undetected mutant'
