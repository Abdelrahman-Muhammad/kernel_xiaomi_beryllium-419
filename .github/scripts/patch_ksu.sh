#!/bin/bash
set -e

sed -i 's@^#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 8, 0)$@#if 0 /* 4.19-CIP already provides copy_to_kernel_nofault() */@' \
  drivers/kernelsu/hook/patch_memory.c

sed -i 's@defined(KSU_HAS_PATH_UMOUNT)@0@g' drivers/kernelsu/feature/kernel_umount.c
sed -i 's@ccflags-y += -DKSU_HAS_PATH_UMOUNT@# ccflags-y += -DKSU_HAS_PATH_UMOUNT@g' drivers/kernelsu/Kbuild

sed -i '/manager_identity.h/a #include "manager/throne_tracker.h"' drivers/kernelsu/supercall/supercall.c
sed -i '/if (magic2 == KSU_INSTALL_MAGIC2) {/a \		if (!ksu_is_manager_appid_valid()) track_throne(false);' drivers/kernelsu/supercall/supercall.c

cat << 'EOF' >> drivers/kernelsu/supercall/supercall.c

#include "ksu.h"
#include "manager/throne_tracker.h"

int ksu_handle_prctl(int option, unsigned long arg2, unsigned long arg3,
		     unsigned long arg4, unsigned long arg5)
{
	if (option != KSU_INSTALL_MAGIC1)
		return -EINVAL;

	if (!ksu_is_manager_appid_valid()) {
		track_throne(false);
	}

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
