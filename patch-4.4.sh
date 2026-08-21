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

# --- 2. user_arg_ptr: needed by sulog/sucompat; kernel 4.4 defines it only in
#        fs/exec.c (local), so provide a compatible copy in this compilation unit ---
if 'KSU_HAVE_USER_ARG_PTR' not in c:
    uap = '''

/*
 * KernelSU compat: Linux >=5.1 exposes struct user_arg_ptr via headers;
 * on 4.4/4.9 (Huawei hi6250) it is local to fs/exec.c. Provide a matching
 * definition so sulog / sucompat compile in a separate translation unit.
 */
#ifndef KSU_HAVE_USER_ARG_PTR
#define KSU_HAVE_USER_ARG_PTR
#include <linux/types.h>
#include <linux/compat.h>
struct user_arg_ptr {
#ifdef CONFIG_COMPAT
	bool is_compat;
#endif
	union {
		const char __user *const __user *native;
#ifdef CONFIG_COMPAT
		const compat_uptr_t __user *compat;
#endif
	} ptr;
};
static inline const char __user *ksu_compat_get_user_arg_ptr(struct user_arg_ptr argv, int nr)
{
	const char __user *native;
#ifdef CONFIG_COMPAT
	if (unlikely(argv.is_compat)) {
		compat_uptr_t compat;
		if (get_user(compat, argv.ptr.compat + nr))
			return ERR_PTR(-EFAULT);
		return compat_ptr(compat);
	}
#endif
	if (get_user(native, argv.ptr.native + nr))
		return ERR_PTR(-EFAULT);
	return native;
}
#define get_user_arg_ptr ksu_compat_get_user_arg_ptr
#endif
'''
    # insert before the final #endif of the include guard
    c = read(p)
    tail_marker = '\n#endif // __KSU_H_KERNEL_INCLUDES'
    if tail_marker in c:
        c = c.replace(tail_marker, uap + '\n' + tail_marker, 1)
        write(p, c)
        print('  [OK] user_arg_ptr compat added to kernel_includes.h')
    else:
        print('  [WARN] could not locate include-guard tail')

# --- 3. selinux_hide (5.10+ only): gate calls in ksud.c ---
p = ksu + '/runtime/ksud.c'
c = read(p)
subs = [
    ('    ksu_selinux_hide_handle_post_fs_data();',
     '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n    ksu_selinux_hide_handle_post_fs_data();\n#endif'),
    ('    ksu_selinux_hide_drop_backup_if_unused();',
     '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n    ksu_selinux_hide_drop_backup_if_unused();\n#endif'),
    ('                ksu_selinux_hide_handle_second_stage();',
     '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n                ksu_selinux_hide_handle_second_stage();\n#endif'),
    ('            ksu_selinux_hide_handle_second_stage();',
     '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n            ksu_selinux_hide_handle_second_stage();\n#endif'),
]
changed = False
for old, new in subs:
    if old in c and '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)' + '\n' + old not in c:
        c = c.replace(old, new, 1)
        changed = True
if changed:
    write(p, c)
    print('  [OK] selinux_hide calls gated in ksud.c')

# --- 4. ksu.c: gate selinux_hide init call; keep sulog headers available (declarations needed) ---
p = ksu + '/ksu.c'
c = read(p)
old = '    ksu_selinux_hide_init();'
if old in c:
    c = c.replace(old, '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)\n    ksu_selinux_hide_init();\n#endif', 1)
    write(p, c)
    print('  [OK] selinux_hide init gated in ksu.c')

print('  [OK] patch complete')
PYEOF

echo "[+] SukiSU 4.4 patch applied."
