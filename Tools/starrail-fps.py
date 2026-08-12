#!/usr/bin/env python3
import re
import sys
import json

REG_PATH = sys.argv[1] if len(sys.argv) > 1 else "/home/kb/Games/starrail-prefix/user.reg"
TARGET_FPS = int(sys.argv[2]) if len(sys.argv) > 2 else 120

with open(REG_PATH, encoding="utf-8") as f:
    content = f.read()

pattern = re.compile(r'("GraphicsSettings_Model_h\d+"=hex:)((?:[0-9a-fA-F]{2},(?:\s*\\?\s*)?)+)', re.M)

def decode_and_modify(m):
    header, hexdata = m.group(1), m.group(2)
    hexstr = re.sub(r'[\\\s]', '', hexdata).replace(',', '')
    try:
        data = bytes.fromhex(hexstr)
        s = data.rstrip(b'\x00').decode('utf-8', errors='replace')
        obj = json.loads(s[s.index('{'):s.rindex('}')+1])
    except Exception as e:
        print(f"[fps-reg] 解析失败: {e}", file=sys.stderr)
        return m.group(0)
    old = obj.get('FPS')
    if old == TARGET_FPS:
        print(f"[fps-reg] FPS 已是 {TARGET_FPS}，跳过")
        return m.group(0)
    obj['FPS'] = TARGET_FPS
    new_bytes = json.dumps(obj, separators=(',', ':')).encode('utf-8') + b'\x00'
    new_hex = ','.join(f'{b:02x}' for b in new_bytes) + ','
    chunks = [new_hex[i:i+76] for i in range(0, len(new_hex), 76)]
    for i in range(1, len(chunks)):
        if not chunks[i-1].endswith(','):
            cut = chunks[i-1].rfind(',')
            if cut != -1:
                overflow = chunks[i-1][cut+1:]
                chunks[i-1] = chunks[i-1][:cut+1]
                chunks[i] = overflow + chunks[i]
    lines = []
    for idx, c in enumerate(chunks):
        if idx == 0:
            lines.append(c)
        else:
            lines.append('  ' + c)
    formatted = '\\\n'.join(lines)
    print(f"[fps-reg] FPS: {old} -> {TARGET_FPS}")
    return header + formatted

new_content, n = pattern.subn(decode_and_modify, content)
if n == 0:
    print("[fps-reg] 未找到 GraphicsSettings_Model 键", file=sys.stderr)
    sys.exit(1)

with open(REG_PATH, "w", encoding="utf-8") as f:
    f.write(new_content)
print(f"[fps-reg] 完成 ({n} 处)")
