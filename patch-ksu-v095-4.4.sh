#!/bin/bash
# Patch official KernelSU v0.9.5 for Huawei Kirin 4.4.23 compatibility.
# Run from kernel source root (where drivers/kernelsu lives).
set -e

echo "[+] Patching KernelSU v0.9.5 for 4.4..."

# 1. Huawei 4.4 has no current_security() macro; use current_cred()->security
f="drivers/kernelsu/selinux/selinux.c"
if grep -q "current_security()" "$f"; then
    sed -i 's/const struct task_security_struct \*tsec = current_security();/const struct task_security_struct *tsec = (const struct task_security_struct *)current_cred()->security;/' "$f"
    echo "  [OK] current_security -> current_cred()->security"
else
    echo "  [WARN] current_security not found (already patched?)"
fi

# 2. Huawei 4.4 groups_sort() is static (not exported); inline a shell sort for <4.9
python3 - <<'PYEOF'
import io

path = 'drivers/kernelsu/core_hook.c'
with io.open(path, 'r', encoding='utf-8') as f:
    c = f.read()

needle = '\tgroups_sort(group_info);\n\tset_groups(cred, group_info);'
repl = """#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 9, 0)
\t{
\t\t/* groups_sort is static in kernel/groups.c on 4.4; inline a simple shell sort */
\t\tint base, max, stride;
\t\tint gidsetsize = group_info->ngroups;
\t\tfor (stride = 1; stride < gidsetsize; stride = 3 * stride + 1) ;
\t\tstride /= 3;
\t\twhile (stride) {
\t\t\tmax = gidsetsize - stride;
\t\t\tfor (base = 0; base < max; base++) {
\t\t\t\tint left = base;
\t\t\t\tint right = left + stride;
\t\t\t\tkgid_t tmp = GROUP_AT(group_info, right);
\t\t\t\twhile (left >= 0 && gid_gt(GROUP_AT(group_info, left), tmp)) {
\t\t\t\t\tGROUP_AT(group_info, right) = GROUP_AT(group_info, left);
\t\t\t\t\tright = left;
\t\t\t\t\tleft -= stride;
\t\t\t\t}
\t\t\t\tGROUP_AT(group_info, right) = tmp;
\t\t\t}
\t\t\tstride /= 3;
\t\t}
\t}
#else
\tgroups_sort(group_info);
#endif
\tset_groups(cred, group_info);"""

if needle in c:
    c = c.replace(needle, repl)
    with io.open(path, 'w', encoding='utf-8') as f:
        f.write(c)
    print('  [OK] groups_sort inlined for 4.4')
else:
    print('  [WARN] groups_sort pattern not found (already patched?)')
PYEOF

echo "[+] KernelSU v0.9.5 4.4 patch applied."
