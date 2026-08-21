#!/bin/bash
# Patch SukiSU-Ultra kernel code for Linux 4.4 compatibility.
# Run from kernel source root (where drivers/kernelsu lives).
set -e

KSU=drivers/kernelsu
echo "[+] Patching SukiSU for 4.4 compatibility..."

python - <<'PYEOF'
import io

def read(p):
    with io.open(p, 'r', encoding='utf-8') as f:
        return f.read()

def write(p, c):
    with io.open(p, 'w', encoding='utf-8') as f:
        f.write(c)

ksu = 'drivers/kernelsu'

# --- 1. fallthrough macro (GCC <7 / kernels <5.10) ---
p = ksu + '/kernel_includes.h'
c = read(p)
if 'define fallthrough' not in c:
    guard = '#define __KSU_H_KERNEL_INCLUDES'
    macro = (guard + '\n\n'
             '#ifndef fallthrough\n'
             '#define fallthrough do {} while (0)  /* fall through */\n'
             '#endif')
    c = c.replace(guard, macro, 1)
    write(p, c)
    print('  [OK] fallthrough macro added')

# --- 2. user_arg_ptr: SukiSU already provides struct user_arg_ptr in ksud.h;
#        do NOT redefine it. get_user_arg_ptr externs are behind CONFIG_KSU_SUSFS
#        which we keep off. Nothing to patch here. ---

# --- 3. selinux_hide (5.10+ only): gate calls in ksud.c ---
p = ksu + '/runtime/ksud.c'
c = read(p)
import re
# gate any standalone selinux_hide call not already wrapped
def gate_call(text, fnname):
    # matches an indented call not preceded by the gate
    pat = re.compile(r'^([ \t]+)' + re.escape(fnname) + r'\(\);\s*$', re.M)
    out = []
    pos = 0
    n = 0
    for m in pat.finditer(text):
        pre = text[:m.start()]
        # skip if already wrapped
        if re.search(r'#if LINUX_VERSION_CODE >= KERNEL_VERSION\(5, 10, 0\)\s*\Z', pre):
            continue
        indent = m.group(1)
        out.append(text[pos:m.start()])
        out.append('#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n')
        out.append(m.group(0) + '\n')
        out.append('#endif\n')
        pos = m.end()
        n += 1
    out.append(text[pos:])
    return ''.join(out), n

c, n1 = gate_call(c, 'ksu_selinux_hide_handle_post_fs_data')
c, n2 = gate_call(c, 'ksu_selinux_hide_drop_backup_if_unused')
c, n3 = gate_call(c, 'ksu_selinux_hide_handle_second_stage')
if n1 + n2 + n3:
    write(p, c)
    print('  [OK] selinux_hide calls gated in ksud.c (%d)' % (n1 + n2 + n3))

# --- 4. ksu.c: gate selinux_hide init call; keep sulog headers available (declarations needed) ---
p = ksu + '/ksu.c'
c = read(p)
old = '    ksu_selinux_hide_init();'
if old in c:
    c = c.replace(old, '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n    ksu_selinux_hide_init();\n#endif', 1)
    write(p, c)
    print('  [OK] selinux_hide init gated in ksu.c')

# --- 5. sulog/event.c: USER_ARG_NULL is a pointer but ksu_sulog_capture wants value ---
p = ksu + '/sulog/event.c'
c = read(p)
old_call = '    pending = ksu_sulog_capture(KSU_SULOG_EVENT_IOCTL_GRANT_ROOT, NULL, USER_ARG_NULL, gfp);'
if old_call in c:
    # re-point the call to dereference the pointer macro
    c = c.replace(old_call,
                  '    pending = ksu_sulog_capture(KSU_SULOG_EVENT_IOCTL_GRANT_ROOT, NULL, *USER_ARG_NULL, gfp);', 1)
    write(p, c)
    print('  [OK] USER_ARG_NULL dereferenced in event.c')

print('  [OK] patch complete')
PYEOF

echo "[+] SukiSU 4.4 patch applied."
