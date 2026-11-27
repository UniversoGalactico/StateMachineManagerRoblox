"""Analyze the library under the official CLI; only Roblox's task global is stubbed."""
import argparse,pathlib,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--analyzer',required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
 paths=[]
 for filename in ('StateMachineManagerRoblox.lua','StateMachineGroup.lua'):
  source=(root/filename).read_text()
  assert source.startswith('--!strict\n')
  path=pathlib.Path(tmp)/filename
  path.write_text(source.replace('--!strict\n','--!strict\nlocal task: any = nil -- CLI-only typecheck stub\n',1))
  paths.append(str(path))
 subprocess.run([a.analyzer,*paths],check=True)
