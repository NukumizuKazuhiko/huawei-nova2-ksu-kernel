#!/bin/bash
# Patch SukiSU-Ultra kernel code for Linux 4.4 compatibility.
# Run from kernel source root (where drivers/kernelsu lives).
set -e

KSU=drivers/kernelsu
echo "[+] Patching SukiSU for 4.4 compatibility..."

# --- 1. fallthrough macro (GCC <7 / kernels <5.10) ---
if ! grep -q "^#define fallthrough" "$KSU/kernel_includes.h"; then
    sed -i 's|^#define __KSU_H_KERNEL_INCLUDES|#define __KSU_H_KERNEL_INCLUDES\n\n#ifndef fallthrough\n#define fallthrough\ndo {} while (0)  /* fall through */\n#endif|' "$KSU/kernel_includes.h"
    echo "  [OK] fallthrough macro added"
else
    echo "  [--] fallthrough already present"
fi

# --- 2. selinux_hide (5.10+ only): gate calls in ksud.c ---
python - <<'EOF'
import re, io

def patch(path, subs):
    with io.open(path, 'r', encoding='utf-8') as f:
        c = f.read()
    orig = c
    for old, new in subs:
        if old in c:
            c = c.replace(old, new, 1)
    if c != orig:
        with io.open(path, 'w', encoding='utf-8') as f:
            f.write(c)
        return True
    return False

ksu = 'drivers/kernelsu'

# ksud.c: gate selinux_hide calls
patch(ksu + '/runtime/ksud.c', [
    ('    ksu_selinux_hide_handle_post_fs_data();',
     '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n    ksu_selinux_hide_handle_post_fs_data();\n#endif'),
    ('    ksu_selinux_hide_drop_backup_if_unused();',
     '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n    ksu_selinux_hide_drop_backup_if_unused();\n#endif'),
])
# the two second_stage calls share identical indentation; handle both occurrences
c = io.open(ksu + '/runtime/ksud.c', 'r', encoding='utf-8').read()
c = c.replace('                ksu_selinux_hide_handle_second_stage();',
              '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n                ksu_selinux_hide_handle_second_stage();\n#endif')
c = c.replace('            ksu_selinux_hide_handle_second_stage();',
              '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n            ksu_selinux_hide_handle_second_stage();\n#endif')
io.open(ksu + '/runtime/ksud.c', 'w', encoding='utf-8').write(c)

# ksu.c: gate selinux_hide init call + sulog module (needs user_arg_ptr, 5.1+)
c = io.open(ksu + '/ksu.c', 'r', encoding='utf-8').read()
c = c.replace('    ksu_selinux_hide_init();',
              '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n    ksu_selinux_hide_init();\n#endif')
# gate sulog header includes
c = c.replace('#include "feature/sulog.h"',
              '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 1, 0)\n#include "feature/sulog.h"\n#endif')
c = c.replace('#include "sulog/event.h"',
              '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 1, 0)\n#include "sulog/event.h"\n#endif')
c = c.replace('#include "sulog/fd.h"',
              '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 1, 0)\n#include "sulog/fd.h"\n#endif')
# gate sulog .c includes (unity build)
c = c.replace('#include "feature/sulog.c"',
              '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 1, 0)\n#include "feature/sulog.c"\n#endif')
c = c.replace('#include "sulog/event.c"',
              '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 1, 0)\n#include "sulog/event.c"\n#endif')
c = c.replace('#include "sulog/fd.c"',
              '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 1, 0)\n#include "sulog/fd.c"\n#endif')
# gate sulog init call
c = c.replace('    ksu_sulog_init();',
              '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 1, 0)\n    ksu_sulog_init();\n#endif')
io.open(ksu + '/ksu.c', 'w', encoding='utf-8').write(c)

# dispatch.c: gate ksu_sulog_emit_grant_root call
c = io.open(ksu + '/supercall/dispatch.c', 'r', encoding='utf-8').read()
c = c.replace('    ksu_sulog_emit_grant_root(ret, audit_uid, audit_euid, GFP_KERNEL);',
              '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 1, 0)\n    ksu_sulog_emit_grant_root(ret, audit_uid, audit_euid, GFP_KERNEL);\n#endif')
io.open(ksu + '/supercall/dispatch.c', 'w', encoding='utf-8').write(c)

print('  [OK] selinux_hide + sulog gated for 4.4')
EOF

echo "[+] SukiSU 4.4 patch applied."
