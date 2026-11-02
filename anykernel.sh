### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=KernelSU-Next by osm0sis @ xda-developers
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=beryllium
device.name2=Poco F1
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot files attributes
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

# boot shell variables
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
dump_boot; # use split_boot to skip ramdisk unpack, e.g. for devices with init_boot ramdisk

write_boot; # use flash_boot to skip ramdisk repack, e.g. for devices with init_boot ramdisk

# KernelSU userspace setup
ak_home="${AKHOME:-$home}";
ak_home="${ak_home:-$PWD}";
if [ -f "$ak_home/ksud" ]; then
  ui_print " ";
  ui_print "- Checking /data for KernelSU userspace...";
  if ! mountpoint -q /data 2>/dev/null && ! grep -q " /data " /proc/mounts 2>/dev/null; then
    mount /data 2>/dev/null || mount /dev/block/bootdevice/by-name/userdata /data 2>/dev/null;
  fi;

  is_data_mounted=0;
  if mountpoint -q /data 2>/dev/null || grep -q " /data " /proc/mounts 2>/dev/null; then
    is_data_mounted=1;
  fi;

  if [ "$is_data_mounted" = "1" ] && [ -w /data ]; then
    if mkdir -p /data/adb 2>/dev/null; then
      chmod 700 /data/adb;
      chown 0:0 /data/adb;
      chcon u:object_r:adb_data_file:s0 /data/adb 2>/dev/null;

      mkdir -p /data/adb/ksu/bin;
      mkdir -p /data/adb/modules;
      mkdir -p /data/adb/modules_update;

      # Non-destructive fallback: only copy ksud if missing
      if [ ! -f /data/adb/ksud ]; then
        ui_print "- Installing ksud...";
        cp -f "$ak_home/ksud" /data/adb/ksud;
      else
        ui_print "- Existing ksud found, preserving.";
      fi;

      # Non-destructive fallback: only copy busybox if missing
      if [ ! -f /data/adb/ksu/bin/busybox ]; then
        ui_print "- Installing busybox...";
        cp -f "$ak_home/busybox" /data/adb/ksu/bin/busybox;
      else
        ui_print "- Existing busybox found, preserving.";
      fi;

      # Symlink ksud and resetprop if missing
      if [ ! -e /data/adb/ksu/bin/ksud ]; then
        ln -sf /data/adb/ksud /data/adb/ksu/bin/ksud;
      fi;
      if [ ! -e /data/adb/ksu/bin/resetprop ]; then
        ln -sf /data/adb/ksud /data/adb/ksu/bin/resetprop;
      fi;

      # Ensure correct permissions, ownership, and SELinux contexts
      chmod 0755 /data/adb/ksud 2>/dev/null;
      chown 0:0 /data/adb/ksud 2>/dev/null;
      chcon u:object_r:adb_data_file:s0 /data/adb/ksud 2>/dev/null;

      chmod 0755 /data/adb/ksu/bin/busybox 2>/dev/null;
      chown 0:0 /data/adb/ksu/bin/busybox 2>/dev/null;
      chcon u:object_r:adb_data_file:s0 /data/adb/ksu/bin/busybox 2>/dev/null;

      chmod -R 0755 /data/adb/ksu/bin 2>/dev/null;
      chown -R 0:0 /data/adb/ksu 2>/dev/null;
      chcon -R u:object_r:adb_data_file:s0 /data/adb/ksu 2>/dev/null;

      ui_print "- KernelSU userspace ready!";
    else
      ui_print "- Warning: /data/adb cannot be created. /data may be encrypted.";
    fi;
  else
    ui_print "- Warning: /data is not mounted or writable. Skipping userspace setup.";
  fi;
fi;

## end boot install
