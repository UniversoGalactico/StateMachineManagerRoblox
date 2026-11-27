import argparse,pathlib,subprocess,tempfile
p=argparse.ArgumentParser()
p.add_argument('--luau',required=True)
p.add_argument('--optimization',default='2')
a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
source=(root/'StateMachineManagerRoblox.lua').read_text()
group=(root/'StateMachineGroup.lua').read_text()
tests=(root/'tests/regression.luau').read_text().replace('print("PASS "..count.." suites")','')+'\n'+(root/'tests/group.luau').read_text()+'\nprint("PASS "..count.." suites")'
with tempfile.TemporaryDirectory() as tmp:
 path=pathlib.Path(tmp)/'test.luau'
 path.write_text('local StateMachine=(function()\n'+source+'\nend)()\nlocal StateMachineGroup=(function()\n'+group+'\nend)()\n'+tests)
 subprocess.run([a.luau,'-O'+a.optimization,str(path)],check=True)
