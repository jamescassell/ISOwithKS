#!/usr/bin/env sh
# Automatically add the company custom kickstart file to a UEFI CD Image
#
# Based on notes from:
#  - http://www.tuxfixer.com/mount-modify-edit-repack-create-uefi-iso-including-kickstart-file/
#  - https://github.com/CentOS/Community-Kickstarts
#set -x
set -e

# TODO:
# - Use the ISO name to pull in kickstart and other info, don't code into script directly.
#   --> ${ISONAME}-info.sh
# - Setup flags in the info.sh file to enable code here.
#   --> ex: SETUP_UEFI=1 --> enables the UEFI code, otherwise not.
#   --> Assume that a portion must be enabled (1), otherwise it is not executed.

#################################
# Global variables to tweak.
#
# Location to build IOS in
BUILDROOT=/opt/rh/tmp/
# Source of the RHEL ISOs - this can be a directory with symlinks.
GOLDENISO=./isos/

# Timestamp for the image:
TS=$(date +%Y%m%d_%H%M%S)

#################################
# Ensure root permissions
if [ `id -u` -gt 0 ] ; then
  echo Must run as root...
  sudo $0 $*
  exit
fi

#################################
# Code to catch an exit and cleanup temp files.
#
function clean_exit {
  echo "Exiting using exit function."
  if [ ! -z "${BUILDDIR}" ] ; then
    umount ${BUILDDIR}/isomount/
#    rmdir ${BUILDDIR}/isomount/
#    rmdir ${BUILDDIR}/
  fi
}
trap clean_exit EXIT

#################################
# Show user the possible ISO files to use
if [ $(ls -1 ${GOLDENISO}/ | wc -l) -le 0 ] ; then
  echo "No files found in the ISO source directory, exiting."
  exit 1
fi

echo "List of available ISOs"
ls -1 ${GOLDENISO}/ | egrep -i iso$ | cat -n
ISONAME="bogus"
if [ ! -z "$1" ] ; then
  ISONAME="$1"
  echo "Using command line ISO: ${ISONAME}"
fi

while [ ! -e "${GOLDENISO}/${ISONAME}" ] ; do
  read -p "Please enter the full name of the ISO to use: " -i "${ISONAME}" ISONAME
  if [ ! -e "${GOLDENISO}/${ISONAME}" ] ; then
    echo "Invalid ISO name.  Try again."
  fi
done

ISONAME=$(basename "${ISONAME}" .iso)

if [ ! -e ./media_info/${ISONAME}.info.sh ] ; then
  echo "Missing media info file: ./media_info/${ISONAME}.info.sh "
  exit 1
fi

source "./media_info/${ISONAME}.info.sh"

if [ -z "${KSNAME}" ] ; then
  echo "Missing name of kickstart file to use."
  exit 1
fi

# Setup the location to hold temporary files and build the ISO.
BUILDDIR="${BUILDROOT}/${ISONAME}_tempdir"

# Ensure temporary directories exist.
mkdir -p ${BUILDDIR}/
mkdir -p ${BUILDDIR}/isomount/
mkdir -p ${BUILDDIR}/image/

# Mount the ISO
mount -o loop ${GOLDENISO}/${ISONAME}.iso ${BUILDDIR}/isomount/

# Cleanup from past tests
rm -f ${BUILDDIR}/${MBR_MENUFILE}* ${BUILDDIR}/image/ks.cfg* ${BUILDDIR}/${UEFI_MENUFILE}*

# Copy contents of ISO to new working directory
echo "Copying contents from ISO to ${BUILDDIR}/image/"
rsync -a ${BUILDDIR}/isomount/ ${BUILDDIR}/image/

# Copy the kickstart file into the ISO directory
rsync -a ./ksfiles/${KSNAME} ${BUILDDIR}/image/ks.cfg

#ls -altr ${BUILDDIR}/${MBR_MENUFILE}* ${BUILDDIR}/image/ks.cfg* ${BUILDDIR}/${UEFI_MENUFILE}*
#read -p "Pausing after copy, press return to continue." foo

#set -x
if [ ${DO_UEFI} -ge 1 ] ; then
  #################################
  # Setup the EFI portion of the boot files (modern systems)
  #
  # Edit the grub.conf in the ../EFI/BOOT/ directory:
  # 1: Change the menuentry title of the first entry:
  echo "===== Setting up UEFI boot options ====="
  sed -i.$(date +%s) "0,/${UEFI_FIND}/s//ABCDEFGHIJ\n${UEFI_FIND}/" ${BUILDDIR}/image/EFI/BOOT/grub.cfg
  sleep 1
  
  # 2: Insert new text:
  INJECT=$(echo "${UEFI_MENU}" | sed ':a;N;$!ba;s/\n/\\n/g')
  sed -i.$(date +%s) "s#ABCDEFGHIJ#${INJECT}#" ${BUILDDIR}/image/EFI/BOOT/grub.cfg
  sleep 1
  
  # 3: Set default boot to the first one we setup:
  sed -i.$(date +%s) 's/^set default=.../set default="0"/' ${BUILDDIR}/image/EFI/BOOT/grub.cfg
  sleep 1
  echo "Updated: ${BUILDDIR}/image/EFI/BOOT/grub.cfg"
#  read -p "Pausing after UEFI settings, press return to continue." foo
fi

if [ ${DO_MBR} -ge 1 ] ; then
  #################################
  # Setup the legacy portion of the boot files
  #
  # 1: Edit the isolinux.cft to use the new kickstart file.
  echo "===== Setting up legacy/MBR boot options ====="
  sed -i.$(date +%s) "0,/${MBR_FIND}/s//${MBR_MENU}/" ${BUILDDIR}/${MBR_MENUFILE}
  sleep 1
  echo "Updated: ${BUILDDIR}/${MBR_MENUFILE}"
#  read -p "Pausing after MBR settings, press return to continue." foo
fi

#################################
# Now build the ISO image
#
# mkisofs -o /tmp/rhel_7.2_uefi_custom.iso -b isolinux/isolinux.bin \
#         -J -R -l -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 \
#         -boot-info-table -eltorito-alt-boot -e images/efiboot.img \
#         -no-emul-boot -graft-points -V "RHEL-7.2 Server.x86_64" \
#         /mnt/custom_rhel72_image/
# -J - Generate Joliet directory records in addition to regular ISO9660 filenames.
# -R - Generate SUSP and RR records using the Rock Ridge protocol
# -l - Allow full 31-character filenames.
# -c - Specifies the path and filename of the boot catalog,
# -V - Specifies  the  volume  ID (volume name or label) to be written into the master block.
# -boot-load-size - Specifies the number of "virtual" (512-byte) sectors to load in no-emulation mode.
# -no-emul-boot - Specifies  that  the boot image used to create El Torito bootable CDs is a "no emulation" image.
# -b - Specifies  the  path  and filename of the boot image to be used when making an El Torito bootable CD

echo "Executing the \"mkisofs\" command."
# Notes: https://fedoraproject.org/wiki/User:Pjones/BootableCDsForBIOSAndUEFI
# mkisofs -o ${BUILDDIR}/custom-${ISONAME}.iso -b isolinux/isolinux.bin \
#         -J -input-charset UTF-8 -R -l -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 \
#         -boot-info-table -eltorito-alt-boot -e images/efiboot.img \
#         -no-emul-boot -graft-points -V "${CDLABEL}" \
#         ${BUILDDIR}/image/ 2>&1 | egrep -v 'estimate finish|^Using\ .*for\ '
mkisofs -U  -A "${CDLABEL}" -V "${CDLABEL}" -volset "${CDLABEL}" -J  -joliet-long -r -v -T \
    -o ${BUILDDIR}/custom-${ISONAME}.iso -b isolinux/isolinux.bin -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot \
    -e images/efiboot.img -no-emul-boot \
    ${BUILDDIR}/image/ 2>&1 | egrep -v 'estimate finish|^Using\ .*for\ '

echo "Execution of \"mkisofs\" complete."
sha256sum  ${BUILDDIR}/custom-${ISONAME}.iso > ${BUILDDIR}/custom-${ISONAME}.iso.sha256sum
echo ""
echo "Built ISO available here:"
echo "${BUILDDIR}/custom-${ISONAME}.iso"
ls -al "${BUILDDIR}/custom-${ISONAME}.iso*"


