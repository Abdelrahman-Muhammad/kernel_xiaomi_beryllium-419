#!/bin/bash
set -e

# Fail loudly if an upstream change makes one of the seds below a no-op.
require() {
	grep -Fq "$1" "$2" || {
		echo "ERROR: expected '$1' in $2; KernelSU-Next source changed" >&2
		exit 1
	}
}

forbid() {
	if grep -Fq "$1" "$2"; then
		echo "ERROR: unwanted '$1' still present in $2" >&2
		exit 1
	fi
}

# 4.19-CIP already provides copy_to_kernel_nofault().
sed -i 's@^#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 8, 0)$@#if 0 /* 4.19-CIP already provides copy_to_kernel_nofault() */@' \
  drivers/kernelsu/hook/patch_memory.c
require '#if 0 /* 4.19-CIP already provides copy_to_kernel_nofault() */' \
  drivers/kernelsu/hook/patch_memory.c

# arm64 4.19 uses pmd_sect()/pud_sect() for the section mappings that
# contain .rodata, so the page-table walk in phys_from_virt() rejects them.
sed -i '/unsigned long phys_from_virt/i #ifndef pmd_leaf\n#define pmd_leaf(pmd) pmd_sect(pmd)\n#endif\n#ifndef pud_leaf\n#define pud_leaf(pud) pud_sect(pud)\n#endif\n' \
  drivers/kernelsu/hook/patch_memory.c
require '#define pmd_leaf(pmd) pmd_sect(pmd)' drivers/kernelsu/hook/patch_memory.c

# Kernel-image addresses (including sys_call_table) are exactly what
# __pa_symbol() translates; bypass the init_mm walk entirely.
sed -i '0,/^[[:space:]]*\*err = 0;$/s//&\n\treturn (unsigned long)__pa_symbol((void *)addr);/' \
  drivers/kernelsu/hook/patch_memory.c
require 'return (unsigned long)__pa_symbol((void *)addr);' \
  drivers/kernelsu/hook/patch_memory.c

# __pa_symbol() lives in asm/memory.h.
sed -i '0,/^#include "patch_memory.h"$/s//&\n#if defined(__aarch64__)\n#include <asm\/memory.h>\n#endif/' \
  drivers/kernelsu/hook/patch_memory.c
require '#include <asm/memory.h>' drivers/kernelsu/hook/patch_memory.c

# Keep setresuid tracing at debug level; it is too noisy at info level.
sed -i 's@pr_info("handle_setresuid from@pr_debug("handle_setresuid from@g' \
  drivers/kernelsu/hook/setuid_hook.c
require 'pr_debug("handle_setresuid from' drivers/kernelsu/hook/setuid_hook.c

# path_umount() is not available on this 4.19 tree.
sed -i 's@defined(KSU_HAS_PATH_UMOUNT)@0@g' drivers/kernelsu/feature/kernel_umount.c
sed -i 's@ccflags-y += -DKSU_HAS_PATH_UMOUNT@# ccflags-y += -DKSU_HAS_PATH_UMOUNT@g' drivers/kernelsu/Kbuild
forbid 'defined(KSU_HAS_PATH_UMOUNT)' drivers/kernelsu/feature/kernel_umount.c
require '# ccflags-y += -DKSU_HAS_PATH_UMOUNT' drivers/kernelsu/Kbuild

# Keep the upstream manager signature check.  Build with
# KSU_NEXT_MANAGER_SIZE / KSU_NEXT_MANAGER_HASH for a custom-signed APK.
require 'return check_v2_signature(path, EXPECTED_MANAGER_SIZE, EXPECTED_MANAGER_HASH);' \
  drivers/kernelsu/manager/apk_sign.c

# The legacy manager interface still uses prctl(0xDEADBEEF, ...).
# Crowning is handled by track_throne() from packages.list; do not let an
# arbitrary app claim the manager appid.
sed -i '/manager_identity.h/a #include "ksu.h"\n#include "manager/throne_tracker.h"' \
  drivers/kernelsu/supercall/supercall.c
require '#include "manager/throne_tracker.h"' drivers/kernelsu/supercall/supercall.c

cat << 'EOF' >> drivers/kernelsu/supercall/supercall.c

int ksu_handle_prctl(int option, unsigned long arg2, unsigned long arg3,
		     unsigned long arg4, unsigned long arg5)
{
	if (option != KSU_INSTALL_MAGIC1)
		return -EINVAL;

	if (!ksu_is_manager_appid_valid())
		track_throne(false);

	if (arg2 == 2) {
		u32 version = KERNEL_SU_VERSION;
		u32 flags = 0;
		u32 features = 0;

		if (is_manager() || current_uid().val == 0) {
			flags |= KSU_GET_INFO_FLAG_MANAGER;
			ksu_install_fd();
		}

		if (arg3 && copy_to_user((void __user *)arg3, &version, sizeof(version)))
			return -EFAULT;

		if (arg4 && copy_to_user((void __user *)arg4, &flags, sizeof(flags)))
			return -EFAULT;

		if (arg5 && copy_to_user((void __user *)arg5, &features, sizeof(features)))
			return -EFAULT;

		return 0;
	}

	if (arg2 == KSU_INSTALL_MAGIC2) {
		struct ksu_install_fd_tw *tw;

		if (current_uid().val != 0 && !allowed_for_su())
			return 0;

		tw = kzalloc(sizeof(*tw), GFP_ATOMIC);
		if (!tw)
			return 0;

		tw->outp = (int __user *)arg3;
		tw->cb.func = ksu_install_fd_tw_func;

		if (task_work_add(current, &tw->cb, TWA_RESUME)) {
			kfree(tw);
			pr_warn("install fd add task_work failed\n");
		}
		return 0;
	}

	return -EINVAL;
}
EOF

require 'int ksu_handle_prctl' drivers/kernelsu/supercall/supercall.c
forbid 'current_uid().val >= 10000' drivers/kernelsu/supercall/supercall.c
