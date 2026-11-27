import argparse,pathlib,subprocess,tempfile
p=argparse.ArgumentParser()
p.add_argument("--luau",required=True)
p.add_argument("--optimization",default="2")
a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
source=(root/"StateMachineManagerRoblox.lua").read_text()
tests=(root/"tests/regression.luau").read_text()
with tempfile.TemporaryDirectory() as tmp:
 path=pathlib.Path(tmp)/"test.luau"
 path.write_text("local StateMachine=(function()\n"+source+"\nend)()\n"+tests)
 subprocess.run([a.luau,"-O"+a.optimization,str(path)],check=True)
