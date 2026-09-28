import subprocess, json, sys
payload = json.dumps({"tool_input": {"file_path": "D:/prime-game/docs/\u0434\u0438\u0437.gd"}}, ensure_ascii=False).encode("utf-8")
flags = 0x08000000  # CREATE_NO_WINDOW
ps = subprocess.run(["powershell.exe","-NoProfile","-Command","$i=[Console]::In.ReadToEnd() | ConvertFrom-Json; Write-Output ('enc=' + [Console]::InputEncoding.WebName); Write-Output ([int[]][char[]]$i.tool_input.file_path -join ',')"], input=payload, capture_output=True, creationflags=flags)
print("PS:", ascii(ps.stdout.decode("utf-8","replace").strip()), "rc", ps.returncode, ascii(ps.stderr[:200]))
py = subprocess.run([sys.executable,"-c","import sys,json;d=json.load(sys.stdin);print('enc='+sys.stdin.encoding, ascii(d['tool_input']['file_path']))"], input=payload, capture_output=True, creationflags=flags)
print("PY default:", py.stdout.decode("utf-8","replace").strip(), "rc", py.returncode, ascii(py.stderr[-150:]))
py2 = subprocess.run([sys.executable,"-c","import sys,json;d=json.loads(sys.stdin.buffer.read().decode('utf-8'));print(ascii(d['tool_input']['file_path']))"], input=payload, capture_output=True, creationflags=flags)
print("PY buffer:", py2.stdout.decode().strip())
print("expected:", ascii("D:/prime-game/docs/\u0434\u0438\u0437.gd"))
