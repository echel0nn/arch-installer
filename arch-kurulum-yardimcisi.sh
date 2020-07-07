# !/bin/bash
#
# Architect Installation Framework (version 2.3.1 - 26-Mar-2016)
#
# Written by Carl Duff for Architect Linux
#
# This program is free software, provided under the GNU General Public License
# as published by the Free Software Foundation. So feel free to copy, distribute,
# or modify it as you wish.
#



######################################################################
##																	##
##                   Installer Variables							##
##																	##
######################################################################

# Temporary files to store menu selections
ANSWER="/tmp/.archinstaller"				# Basic menu selections
PACKAGES="/tmp/.pkgs"			# Packages to install
MOUNT_OPTS="/tmp/.mnt_opts" 	# Filesystem Mount options

# Save retyping
VERSION="Arch Linux Türkçe Kurulum Yardımcısı"

# Installation
DM_INST=""							# Which DMs have been installed?
DM_ENABLED=0						# Has a display manager been enabled?
NM_INST=""							# Which NMs have been installed?
NM_ENABLED=0						# Has a network connection manager been enabled?
KERNEL="n"                			# Kernel(s) installed (base install); kernels for mkinitcpio
GRAPHIC_CARD=""						# graphics card
INTEGRATED_GC=""					# Integrated graphics card for NVIDIA
NVIDIA_INST=0         				# Indicates if NVIDIA proprietary driver has been installed
NVIDIA=""							# NVIDIA driver(s) to install depending on kernel(s)
VB_MOD=""							# headers packages to install depending on kernel(s)
SHOW_ONCE=0           				# Show de_wm information only once
COPY_PACCONF=0						# Copy over installer /etc/pacman.conf to installed system?
BOOT_EFI32=0                        # 1 If the bootloader the EFI is 32bit. 0 if not UEFI or 64bit UEFI
# Mounting
MOUNTPOINT="/mnt"       			# Installation: Root mount
MOUNT=""							# Installation: All other mounts branching from Root
FS_OPTS=""							# File system special mount options available
CHK_NUM=16							# Used for FS mount options checklist length
INCLUDE_PART='part\|lvm\|crypt'		# Partition types to include for display and selection.
ROOT_PART=""          				# ROOT partition
UEFI_PART=""						# UEFI partition
UEFI_MOUNT=""         				# UEFI mountpoint (/boot or /boot/efi)

# Architecture
ARCHI=$(uname -m)     				# Display whether 32 or 64 bit system
SYSTEM="Unknown"     				# Display whether system is BIOS or UEFI. Default is "unknown"

# Menu highlighting (automated step progression)
HIGHLIGHT=0           				# Highlight items for Main Menu
HIGHLIGHT_SUB=0	    				# Highlight items for submenus
SUB_MENU=""           				# Submenu to be highlighted

# Logical Volume Management
LVM=0                   			# Logical Volume Management Detected?
LVM_SEP_BOOT=0          			# 1 = Seperate /boot, 2 = seperate /boot & LVM
LVM_VG=""               			# Name of volume group to create or use
LVM_VG_MB=0             			# MB remaining of VG
LVM_LV_NAME=""          			# Name of LV to create or use
LV_SIZE_INVALID=0       			# Is LVM LV size entered valid?
VG_SIZE_TYPE=""         			# Is VG in Gigabytes or Megabytes?

# LUKS
LUKS=0                  			# Luks Used?
LUKS_DEV=""							# If encrypted, partition
LUKS_NAME=""						# Name given to encrypted partition
LUKS_UUID=""						# UUID used for comparison purposes
LUKS_OPT=""							# Default or user-defined?

# Locale and Language
CURR_LOCALE="en_US.UTF-8"   		# Default Locale
FONT=""                     		# Set new font if necessary
KEYMAP="tr"          				# Virtual console keymap. Default is "us"
XKBMAP="tr"      	    			# X11 keyboard layout. Default is "us"
ZONE=""               				# For time
SUBZONE=""            				# For time
LOCALE="en_US.UTF-8"  				# System locale. Default is "en_US.UTF-8"


# Edit Files
FILE=""                     		# File(s) to be reviewed

######################################################################
##																	##
##                        Core Functions							##
##																	##
######################################################################

# Add locale on-the-fly and sets source translation file for installer
select_language() {
    
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " Dil Seçin: " --menu "\nLanguage / sprache / taal / språk / lingua / idioma / nyelv / língua" 0 0 9 \
 	"1" $"English            (en_**)" \
	"2" $"Türkçe             (tr_TR)" 2>${ANSWER}

	case $(cat ${ANSWER}) in
        "1") source ./english.trans
             CURR_LOCALE="en_US.UTF-8"
             ;;
        "2") source ./turkish.trans
             CURR_LOCALE="tr_TR.UTF-8"
             ;; 
          *) exit 0
             ;;
    esac
        
    # Generate the chosen locale and set the language
    sed -i "s/#${CURR_LOCALE}/${CURR_LOCALE}/" /etc/locale.gen
    locale-gen >/dev/null 2>&1
    export LANG=${CURR_LOCALE}
    [[ $FONT != "" ]] && setfont $FONT
}



# Check user is root, and that there is an active internet connection
# Seperated the checks into seperate "if" statements for readability.
check_requirements() {
	
  dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ChkTitle " --infobox "$_ChkBody" 0 0
  sleep 2
  
  if [[ `whoami` != "root" ]]; then
     dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_Erritle " --infobox "$_RtFailBody" 0 0
     sleep 2
     exit 1
  fi
  
  if [[ ! $(ping -c 1 google.com) ]]; then
     dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --infobox "$_ConFailBody" 0 0
     sleep 2
     exit 1
  fi
  
  # This will only be executed where neither of the above checks are true.
  # The error log is also cleared, just in case something is there from a previous use of the installer.
  dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ReqMetTitle " --infobox "$_ReqMetBody" 0 0
  sleep 2   
  clear
  echo "" > /tmp/.errlog
  pacman -Syy
}

# Adapted from AIS. Checks if system is made by Apple, whether the system is BIOS or UEFI,
# and for LVM and/or LUKS.
id_system() {
	
    # Apple System Detection
    if [[ "$(cat /sys/class/dmi/id/sys_vendor)" == 'Apple Inc.' ]] || [[ "$(cat /sys/class/dmi/id/sys_vendor)" == 'Apple Computer, Inc.' ]]; then
      modprobe -r -q efivars || true  # if MAC
    else
      modprobe -q efivarfs            # all others
    fi
    
    # BIOS or UEFI Detection
    if [[ -d "/sys/firmware/efi/" ]]; then
      # Mount efivarfs if it is not already mounted
      if [[ -z $(mount | grep /sys/firmware/efi/efivars) ]]; then
        mount -t efivarfs efivarfs /sys/firmware/efi/efivars
      fi
      SYSTEM="UEFI"
    else
      SYSTEM="BIOS"
    fi
         

}   
 

# Adapted from AIS. An excellent bit of code!
arch_chroot() {
    arch-chroot $MOUNTPOINT /bin/bash -c "${1}"
}  

# If there is an error, display it, clear the log and then go back to the main menu (no point in continuing).
check_for_error() {

 if [[ $? -eq 1 ]] && [[ $(cat /tmp/.errlog | grep -i "error") != "" ]]; then
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$(cat /tmp/.errlog)" 0 0
    echo "" > /tmp/.errlog
    main_menu_online
 fi
   
}

# Ensure that a partition is mounted
check_mount() {

    if [[ $(lsblk -o MOUNTPOINT | grep ${MOUNTPOINT}) == "" ]]; then
       dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_ErrNoMount" 0 0
       main_menu_online
    fi

}

# Ensure that Arch has been installed
check_base() {

    if [[ ! -e ${MOUNTPOINT}/etc ]]; then
        dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_ErrNoBase" 0 0
        main_menu_online
    fi
    
}

# Simple code to show devices / partitions.
show_devices() {
     lsblk -o NAME,MODEL,TYPE,FSTYPE,SIZE,MOUNTPOINT | grep "disk\|part\|lvm\|crypt\|NAME\|MODEL\|TYPE\|FSTYPE\|SIZE\|MOUNTPOINT" > /tmp/.devlist
     dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_DevShowOpt " --textbox /tmp/.devlist 0 0
}

######################################################################
##																	##
##                 Configuration Functions							##
##																	##
######################################################################


# Originally adapted from AIS. Added option to allow users to edit the mirrorlist.
configure_mirrorlist() {

# Generate a mirrorlist based on the country chosen.	
mirror_by_country() {

 COUNTRY_LIST=""
 countries_list="AU Australia AT Austria BA Bosnia_Herzegovina BY Belarus BE Belgium BR Brazil BG Bulgaria CA Canada CL Chile CN China CO Colombia CZ Czech_Republic DK Denmark EE Estonia FI Finland FR France DE Germany GB United_Kingdom GR Greece HU Hungary IN India IE Ireland IL Israel IT Italy JP Japan KZ Kazakhstan KR Korea LT Lithuania LV Latvia LU Luxembourg MK Macedonia NL Netherlands NC New_Caledonia NZ New_Zealand NO Norway PL Poland PT Portugal RO Romania RU Russia RS Serbia SG Singapore SK Slovakia ZA South_Africa ES Spain LK Sri_Lanka SE Sweden CH Switzerland TW Taiwan TR Turkey UA Ukraine US United_States UZ Uzbekistan VN Vietnam"

 for i in ${countries_list}; do
     COUNTRY_LIST="${COUNTRY_LIST} ${i}"
 done

 dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_MirrorlistTitle " --menu "$_MirrorCntryBody" 0 0 0 $COUNTRY_LIST 2>${ANSWER} || install_base_menu

 URL="https://www.archlinux.org/mirrorlist/?country=$(cat ${ANSWER})&use_mirror_status=on"
 MIRROR_TEMP=$(mktemp --suffix=-mirrorlist)

 # Get latest mirror list and save to tmpfile
 dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_MirrorlistTitle " --infobox "$_PlsWaitBody" 0 0
  
 curl -so ${MIRROR_TEMP} ${URL} 2>/tmp/.errlog
 check_for_error
 sed -i 's/^#Server/Server/g' ${MIRROR_TEMP}
 nano ${MIRROR_TEMP}

 dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_MirrorlistTitle " --yesno "$_MirrorGenQ" 0 0

 if [[ $? -eq 0 ]];then
    mv -f /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.orig
    mv -f ${MIRROR_TEMP} /etc/pacman.d/mirrorlist
    chmod +r /etc/pacman.d/mirrorlist
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_MirrorlistTitle " --infobox "\n$_Done!\n\n" 0 0
	sleep 2
 else
    configure_mirrorlist
 fi
}


dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_MirrorlistTitle " \
    --menu "$_MirrorlistBody" 0 0 6 \
	"1" "$_MirrorbyCountry" \
	"2" "$_MirrorRankTitle" \
	"3" "$_MirrorEdit" \
	"4" "$_MirrorRestTitle" \
	"5" "$_MirrorPacman" \
	"6" "$_Back" 2>${ANSWER}	

    case $(cat ${ANSWER}) in
        "1") mirror_by_country
             ;;
        "2") dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_MirrorlistTitle " --infobox "$_MirrorRankBody $_PlsWaitBody" 0 0
             cp -f /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
             rankmirrors -n 10 /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist 2>/tmp/.errlog
             check_for_error
             dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_MirrorlistTitle " --infobox "\n$_Done!\n\n" 0 0
			 sleep 2
             ;;
        "3") nano /etc/pacman.d/mirrorlist
             ;;
        "4") if [[ -e /etc/pacman.d/mirrorlist.orig ]]; then       
				 mv -f /etc/pacman.d/mirrorlist.orig /etc/pacman.d/mirrorlist
				 dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_MirrorlistTitle " --msgbox "\n$_Done!\n\n" 0 0
		      else
		         dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_MirrorNoneBody" 0 0
		      fi
             ;;
         "5") nano /etc/pacman.conf
			  dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_MirrorPacman " --yesno "$_MIrrorPacQ" 0 0 && COPY_PACCONF=1 || COPY_PACCONF=0
			  pacman -Syy
			;;
		*) install_base_menu
             ;;
    esac  	

    configure_mirrorlist
}

# virtual console keymap
set_keymap() { 
	
	KEYMAPS=""
    for i in $(ls -R /usr/share/kbd/keymaps | grep "map.gz" | sed 's/\.map\.gz//g' | sort); do
        KEYMAPS="${KEYMAPS} ${i} -"
    done
    
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_VCKeymapTitle " \
    --menu "$_VCKeymapBody" 20 40 16 ${KEYMAPS} 2>${ANSWER} || prep_menu 
    KEYMAP=$(cat ${ANSWER})
    
	loadkeys $KEYMAP 2>/tmp/.errlog
    check_for_error

    echo -e "KEYMAP=${KEYMAP}\nFONT=${FONT}" > /tmp/vconsole.conf
  }

# Set keymap for X11
 set_xkbmap() {
	 
	XKBMAP_LIST=""
	keymaps_xkb=("af al am at az ba bd be bg br bt bw by ca cd ch cm cn cz de dk ee es et eu fi fo fr gb ge gh gn gr hr hu ie il in iq ir is it jp ke kg kh kr kz la lk lt lv ma md me mk ml mm mn mt mv ng nl no np pc ph pk pl pt ro rs ru se si sk sn sy tg th tj tm tr tw tz ua us uz vn za")
    
	for i in ${keymaps_xkb}; do
        XKBMAP_LIST="${XKBMAP_LIST} ${i} -"
    done
	
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepKBLayout " --menu "$_XkbmapBody" 0 0 16 ${XKBMAP_LIST} 2>${ANSWER} || install_graphics_menu
    XKBMAP=$(cat ${ANSWER} |sed 's/_.*//')
    echo -e "Section "\"InputClass"\"\nIdentifier "\"system-keyboard"\"\nMatchIsKeyboard "\"on"\"\nOption "\"XkbLayout"\" "\"${XKBMAP}"\"\nEndSection" > ${MOUNTPOINT}/etc/X11/xorg.conf.d/00-keyboard.conf
 
}

# locale array generation code adapted from the Manjaro 0.8 installer
set_locale() {

  LOCALES=""	
  for i in $(cat /etc/locale.gen | grep -v "#  " | sed 's/#//g' | sed 's/ UTF-8//g' | grep .UTF-8); do
      LOCALES="${LOCALES} ${i} -"
  done

  dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfBseSysLoc " --menu "$_localeBody" 0 0 12 ${LOCALES} 2>${ANSWER} || config_base_menu 
  
  LOCALE=$(cat ${ANSWER})

  echo "LANG=\"${LOCALE}\"" > ${MOUNTPOINT}/etc/locale.conf
  sed -i "s/#${LOCALE}/${LOCALE}/" ${MOUNTPOINT}/etc/locale.gen 2>/tmp/.errlog
  arch_chroot "locale-gen" >/dev/null 2>>/tmp/.errlog
  check_for_error
}

# Set Zone and Sub-Zone
set_timezone() {

    ZONE=""
    for i in $(cat /usr/share/zoneinfo/zone.tab | awk '{print $3}' | grep "/" | sed "s/\/.*//g" | sort -ud); do
      ZONE="$ZONE ${i} -"
    done
    
     dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfBseTimeHC " --menu "$_TimeZBody" 0 0 10 ${ZONE} 2>${ANSWER} || config_base_menu
     ZONE=$(cat ${ANSWER}) 
    
     SUBZONE=""
     for i in $(cat /usr/share/zoneinfo/zone.tab | awk '{print $3}' | grep "${ZONE}/" | sed "s/${ZONE}\///g" | sort -ud); do
        SUBZONE="$SUBZONE ${i} -"
     done
         
     dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfBseTimeHC " --menu "$_TimeSubZBody" 0 0 11 ${SUBZONE} 2>${ANSWER} || config_base_menu
     SUBZONE=$(cat ${ANSWER}) 
    
     dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfBseTimeHC " --yesno "$_TimeZQ ${ZONE}/${SUBZONE}?" 0 0 
     
     if [[ $? -eq 0 ]]; then
        arch_chroot "ln -s /usr/share/zoneinfo/${ZONE}/${SUBZONE} /etc/localtime" 2>/tmp/.errlog
        check_for_error
     else
        config_base_menu
     fi
}

set_hw_clock() {
	
   dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfBseTimeHC " --menu "$_HwCBody" 0 0 2 \
 	"utc" "-" "localtime" "-" 2>${ANSWER}	

    [[ $(cat ${ANSWER}) != "" ]] && arch_chroot "hwclock --systohc --$(cat ${ANSWER})"  2>/tmp/.errlog && check_for_error
}

# Function will not allow incorrect UUID type for installed system.
generate_fstab() {

    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfBseFstab " --menu "$_FstabBody" 0 0 4 \
	"genfstab -p" "$_FstabDevName" \
	"genfstab -L -p" "$_FstabDevLabel" \
	"genfstab -U -p" "$_FstabDevUUID" \
	"genfstab -t PARTUUID -p" "$_FstabDevPtUUID" 2>${ANSWER}
	
	if [[ $(cat ${ANSWER}) != "" ]]; then
		if [[ $SYSTEM == "BIOS" ]] && [[ $(cat ${ANSWER}) == "genfstab -t PARTUUID -p" ]]; then
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_FstabErr" 0 0
			generate_fstab
		else
			$(cat ${ANSWER}) ${MOUNTPOINT} > ${MOUNTPOINT}/etc/fstab 2>/tmp/.errlog
			check_for_error
			[[ -f ${MOUNTPOINT}/swapfile ]] && sed -i "s/\\${MOUNTPOINT}//" ${MOUNTPOINT}/etc/fstab
		fi
	fi
	
	config_base_menu

}


set_hostname() {

   dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfBseHost " --inputbox "$_HostNameBody" 0 0 "arch" 2>${ANSWER} || config_base_menu

   echo "$(cat ${ANSWER})" > ${MOUNTPOINT}/etc/hostname 2>/tmp/.errlog
   echo -e "#<ip-address>\t<hostname.domain.org>\t<hostname>\n127.0.0.1\tlocalhost.localdomain\tlocalhost\t$(cat ${ANSWER})\n::1\tlocalhost.localdomain\tlocalhost\t$(cat ${ANSWER})" > ${MOUNTPOINT}/etc/hosts 2>>/tmp/.errlog
   check_for_error
}

# Adapted and simplified from the Manjaro 0.8 and Antergos 2.0 installers
set_root_password() {

    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfUsrRoot " --clear --insecure --passwordbox "$_PassRtBody" 0 0 2> ${ANSWER} || config_base_menu
    PASSWD=$(cat ${ANSWER})
    
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfUsrRoot " --clear --insecure --passwordbox "$_PassReEntBody" 0 0 2> ${ANSWER} || config_base_menu
    PASSWD2=$(cat ${ANSWER})
    
    if [[ $PASSWD == $PASSWD2 ]]; then 
       echo -e "${PASSWD}\n${PASSWD}" > /tmp/.passwd
       arch_chroot "passwd root" < /tmp/.passwd >/dev/null 2>/tmp/.errlog
       rm /tmp/.passwd
       check_for_error
    else
       dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_PassErrBody" 0 0
       set_root_password
    fi

}

# Originally adapted from the Antergos 2.0 installer
create_new_user() {

        dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_NUsrTitle " --inputbox "$_NUsrBody" 0 0 "" 2>${ANSWER} || config_base_menu
        USER=$(cat ${ANSWER})
        
        # Loop while user name is blank, has spaces, or has capital letters in it.
         while [[ ${#USER} -eq 0 ]] || [[ $USER =~ \ |\' ]] || [[ $USER =~ [^a-z0-9\ ] ]]; do
              dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_NUsrTitle " --inputbox "$_NUsrErrBody" 0 0 "" 2>${ANSWER} || config_base_menu
              USER=$(cat ${ANSWER})
        done
        
        # Enter password. This step will only be reached where the loop has been skipped or broken.
        dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfUsrNew " --clear --insecure --passwordbox "$_PassNUsrBody $USER\n\n" 0 0 2> ${ANSWER} || config_base_menu
        PASSWD=$(cat ${ANSWER}) 
    
        dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfUsrNew " --clear --insecure --passwordbox "$_PassReEntBody" 0 0 2> ${ANSWER} || config_base_menu
        PASSWD2=$(cat ${ANSWER}) 
    
        # loop while passwords entered do not match.
        while [[ $PASSWD != $PASSWD2 ]]; do
              dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_PassErrBody" 0 0
              
              dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfUsrNew " --clear --insecure --passwordbox "$_PassNUsrBody $USER\n\n" 0 0 2> ${ANSWER} || config_base_menu
              PASSWD=$(cat ${ANSWER}) 
    
              dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfUsrNew " --clear --insecure --passwordbox "$_PassReEntBody" 0 0 2> ${ANSWER} || config_base_menu
              PASSWD2=$(cat ${ANSWER}) 
        done      
    
        # create new user. This step will only be reached where the password loop has been skipped or broken.  
        dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfUsrNew " --infobox "$_NUsrSetBody" 0 0
        sleep 2
        # Create the user, set password, then remove temporary password file
        arch_chroot "useradd ${USER} -m -g users -G wheel,storage,power,network,video,audio,lp -s /bin/bash" 2>/tmp/.errlog
        check_for_error
        echo -e "${PASSWD}\n${PASSWD}" > /tmp/.passwd
        arch_chroot "passwd ${USER}" < /tmp/.passwd >/dev/null 2>/tmp/.errlog
        rm /tmp/.passwd
        check_for_error
        # Set up basic configuration files and permissions for user
        arch_chroot "cp /etc/skel/.bashrc /home/${USER}"
        arch_chroot "chown -R ${USER}:users /home/${USER}"
        [[ -e ${MOUNTPOINT}/etc/sudoers ]] && sed -i '/%wheel ALL=(ALL) ALL/s/^#//' ${MOUNTPOINT}/etc/sudoers
      
}

run_mkinitcpio() {
	
	clear

	KERNEL=""

	# If LVM and/or LUKS used, add the relevant hook(s)
	([[ $LVM -eq 1 ]] && [[ $LUKS -eq 0 ]]) && sed -i 's/block filesystems/block lvm2 filesystems/g' ${MOUNTPOINT}/etc/mkinitcpio.conf 2>/tmp/.errlog
    ([[ $LVM -eq 1 ]] && [[ $LUKS -eq 1 ]]) && sed -i 's/block filesystems/block encrypt lvm2 filesystems/g' ${MOUNTPOINT}/etc/mkinitcpio.conf 2>/tmp/.errlog
    ([[ $LVM -eq 0 ]] && [[ $LUKS -eq 1 ]]) && sed -i 's/block filesystems/block encrypt filesystems/g' ${MOUNTPOINT}/etc/mkinitcpio.conf 2>/tmp/.errlog
    check_for_error
    
	# Run Mkinitcpio command depending on kernel(s) installed
	KERNEL=$(ls ${MOUNTPOINT}/boot/*.img | grep -v "fallback" | sed "s~${MOUNTPOINT}/boot/initramfs-~~g" | sed s/\.img//g | uniq)
	for i in ${KERNEL}; do
		arch_chroot "mkinitcpio -p ${i}" 2>>/tmp/.errlog
	done
	check_for_error
 
}

######################################################################
##																	##
##            System and Partitioning Functions						##
##																	##
######################################################################



# Unmount partitions.
umount_partitions(){
	
  MOUNTED=""
  MOUNTED=$(mount | grep "${MOUNTPOINT}" | awk '{print $3}' | sort -r)
  swapoff -a
  
  for i in ${MOUNTED[@]}; do
      umount $i >/dev/null 2>>/tmp/.errlog
  done
  
  check_for_error

}

# Revised to deal with partion sizes now being displayed to the user
confirm_mount() {
    if [[ $(mount | grep $1) ]]; then   
      dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_MntStatusTitle " --infobox "$_MntStatusSucc" 0 0
      sleep 2
      PARTITIONS=$(echo $PARTITIONS | sed "s~${PARTITION} [0-9]*[G-M]~~" | sed "s~${PARTITION} [0-9]*\.[0-9]*[G-M]~~" | sed s~${PARTITION}$' -'~~)
      NUMBER_PARTITIONS=$(( NUMBER_PARTITIONS - 1 ))
    else
      dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_MntStatusTitle " --infobox "$_MntStatusFail" 0 0
      sleep 2
      prep_menu
    fi
}

# This function does not assume that the formatted device is the Root installation device as 
# more than one device may be formatted. Root is set in the mount_partitions function.
select_device() {
	
    DEVICE=""
    devices_list=$(lsblk -lno NAME,SIZE,TYPE | grep 'disk' | awk '{print "/dev/" $1 " " $2}' | sort -u);
    
    for i in ${devices_list[@]}; do
        DEVICE="${DEVICE} ${i}"
    done
    
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_DevSelTitle " --menu "$_DevSelBody" 0 0 4 ${DEVICE} 2>${ANSWER} || prep_menu
    DEVICE=$(cat ${ANSWER})
 
  }

# Finds all available partitions according to type(s) specified and generates a list 
# of them. This also includes partitions on different devices.
find_partitions() {

	PARTITIONS=""
	NUMBER_PARTITIONS=0	
	partition_list=$(lsblk -lno NAME,SIZE,TYPE | grep $INCLUDE_PART | sed 's/part$/\/dev\//g' | sed 's/lvm$\|crypt$/\/dev\/mapper\//g' | awk '{print $3$1 " " $2}' | sort -u)

    for i in ${partition_list}; do
        PARTITIONS="${PARTITIONS} ${i}"
        NUMBER_PARTITIONS=$(( NUMBER_PARTITIONS + 1 ))
    done
    
    # Double-partitions will be counted due to counting sizes, so fix    
    NUMBER_PARTITIONS=$(( NUMBER_PARTITIONS / 2 ))

	# Deal with partitioning schemes appropriate to mounting, lvm, and/or luks.
	case $INCLUDE_PART in
	'part\|lvm\|crypt') # Deal with incorrect partitioning for main mounting function

		if ([[ $SYSTEM == "UEFI" ]] && [[ $NUMBER_PARTITIONS -lt 2 ]]) || ([[ $SYSTEM == "BIOS" ]] && [[ $NUMBER_PARTITIONS -eq 0 ]]); then
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_PartErrBody" 0 0
			create_partitions
		fi
		;;
	'part\|crypt') # Ensure there is at least one partition for LVM 
		if [[ $NUMBER_PARTITIONS -eq 0 ]]; then
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_LvmPartErrBody" 0 0
			create_partitions
		fi
		;;
	'part\|lvm') # Ensure there are at least two partitions for LUKS
		if [[ $NUMBER_PARTITIONS -lt 2 ]]; then
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_LuksPartErrBody" 0 0
			create_partitions
		fi
		;;
	esac
    
}

create_partitions(){

# Securely destroy all data on a given device.
secure_wipe(){
	
	# Warn the user. If they proceed, wipe the selected device.
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PartOptWipe " --yesno "$_AutoPartWipeBody1 ${DEVICE} $_AutoPartWipeBody2" 0 0
	if [[ $? -eq 0 ]]; then
		clear
		
		# Install wipe where not already installed. Much faster than dd
		if [[ ! -e /usr/bin/wipe ]]; then
			pacman -Sy --noconfirm wipe 2>/tmp/.errlog
			check_for_error
		fi
		
		clear
		wipe -Ifre ${DEVICE}
		
		# Alternate dd command - requires pv to be installed
		#dd if=/dev/zero | pv | dd of=${DEVICE} iflag=nocache oflag=direct bs=4096 2>/tmp/.errlog
		check_for_error
    else
		create_partitions
    fi
}

# BIOS and UEFI
auto_partition(){
	
	# Provide warning to user
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepPartDisk " --yesno "$_AutoPartBody1 $DEVICE $_AutoPartBody2 $_AutoPartBody3" 0 0
	
	if [[ $? -eq 0 ]]; then
		
		# Find existing partitions (if any) to remove
		parted -s ${DEVICE} print | awk '/^ / {print $1}' > /tmp/.del_parts
	
		for del_part in $(tac /tmp/.del_parts); do
			parted -s ${DEVICE} rm ${del_part} 2>/tmp/.errlog
			check_for_error
		done
 
		# Identify the partition table
		part_table=$(parted -s ${DEVICE} print | grep -i 'partition table' | awk '{print $3}' >/dev/null 2>&1)
 
		# Create partition table if one does not already exist
		([[ $SYSTEM == "BIOS" ]] && [[ $part_table != "msdos" ]]) && parted -s ${DEVICE} mklabel msdos 2>/tmp/.errlog
		([[ $SYSTEM == "UEFI" ]] && [[ $part_table != "gpt" ]]) && parted -s ${DEVICE} mklabel gpt 2>/tmp/.errlog
		check_for_error
		
		# Create paritions (same basic partitioning scheme for BIOS and UEFI)
		if [[ $SYSTEM == "BIOS" ]]; then
			parted -s ${DEVICE} mkpart primary ext3 1MiB 513MiB 2>/tmp/.errlog
		else
			parted -s ${DEVICE} mkpart ESP fat32 1MiB 513MiB 2>/tmp/.errlog
		fi
		
		parted -s ${DEVICE} set 1 boot on 2>>/tmp/.errlog
		parted -s ${DEVICE} mkpart primary ext3 513MiB 100% 2>>/tmp/.errlog
		check_for_error

        # Show created partitions
        lsblk ${DEVICE} -o NAME,TYPE,FSTYPE,SIZE > /tmp/.devlist
        dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title "" --textbox /tmp/.devlist 0 0
    else
        create_partitions
    fi

}

	# Partitioning Menu
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepPartDisk " --menu "$_PartToolBody" 0 0 7 \
    "$_PartOptWipe" "BIOS & UEFI" \
    "$_PartOptAuto" "BIOS & UEFI" \
	"cfdisk" "BIOS" \
	"cgdisk" "UEFI" \
	"fdisk"  "BIOS & UEFI" \
	"gdisk"  "UEFI" \
	"parted" "BIOS & UEFI" 2>${ANSWER}

	clear
	# If something selected
	if [[ $(cat ${ANSWER}) != "" ]]; then
		if ([[ $(cat ${ANSWER}) != "$_PartOptWipe" ]] &&  [[ $(cat ${ANSWER}) != "$_PartOptAuto" ]]); then
			$(cat ${ANSWER}) ${DEVICE}
		else
			[[ $(cat ${ANSWER}) == "$_PartOptWipe" ]] && secure_wipe && create_partitions
			[[ $(cat ${ANSWER}) == "$_PartOptAuto" ]] && auto_partition
		fi
	fi
	
	prep_menu
}	

# Set static list of filesystems rather than on-the-fly. Partially as most require additional flags, and 
# partially because some don't seem to be viable.
# Set static list of filesystems rather than on-the-fly.
select_filesystem(){

	# prep variables
	fs_opts=""
	CHK_NUM=0

	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_FSTitle " --menu "$_FSBody" 0 0 12 \
	"$_FSSkip" "-" \
	"btrfs" "mkfs.btrfs -f" \
	"ext2" "mkfs.ext2 -q" \
	"ext3" "mkfs.ext3 -q" \
	"ext4" "mkfs.ext4 -q" \
	"f2fs" "mkfs.f2fs" \
	"jfs" "mkfs.jfs -q" \
	"nilfs2" "mkfs.nilfs2 -q" \
	"ntfs" "mkfs.ntfs -q" \
	"reiserfs" "mkfs.reiserfs -q" \
	"vfat" "mkfs.vfat -F32" \
	"xfs" "mkfs.xfs -f" 2>${ANSWER}	
	
	case $(cat ${ANSWER}) in
		"$_FSSkip")	FILESYSTEM="$_FSSkip" ;;
		"btrfs") 	FILESYSTEM="mkfs.btrfs -f"	
					CHK_NUM=16
					fs_opts="autodefrag compress=zlib compress=lzo compress=no compress-force=zlib compress-force=lzo discard noacl noatime nodatasum nospace_cache recovery skip_balance space_cache ssd ssd_spread"
					modprobe btrfs
					;;
		"ext2") 	FILESYSTEM="mkfs.ext2 -q" ;;
		"ext3") 	FILESYSTEM="mkfs.ext3 -q" ;;
		"ext4") 	FILESYSTEM="mkfs.ext4 -q"
					CHK_NUM=8
					fs_opts="data=journal data=writeback dealloc discard noacl noatime nobarrier nodelalloc"
					;;
		"f2fs") 	FILESYSTEM="mkfs.f2fs"
					fs_opts="data_flush disable_roll_forward disable_ext_identify discard fastboot flush_merge inline_xattr inline_data inline_dentry no_heap noacl nobarrier noextent_cache noinline_data norecovery"
					CHK_NUM=16
					modprobe f2fs
					;;
		"jfs") 		FILESYSTEM="mkfs.jfs -q" 
					CHK_NUM=4
					fs_opts="discard errors=continue errors=panic nointegrity"
					;;
		"nilfs2") 	FILESYSTEM="mkfs.nilfs2 -q" 
					CHK_NUM=7
					fs_opts="discard nobarrier errors=continue errors=panic order=relaxed order=strict norecovery"
					;;
		"ntfs") 	FILESYSTEM="mkfs.ntfs -q" ;;
		"reiserfs") FILESYSTEM="mkfs.reiserfs -q"
					CHK_NUM=5
					fs_opts="acl nolog notail replayonly user_xattr"
					;;
		"vfat") 	FILESYSTEM="mkfs.vfat -F32" ;;
		"xfs") 		FILESYSTEM="mkfs.xfs -f" 
					CHK_NUM=9
					fs_opts="discard filestreams ikeep largeio noalign nobarrier norecovery noquota wsync"
					;;
		*) 			prep_menu ;;
	esac
	
	# Warn about formatting!
	if [[ $FILESYSTEM != $_FSSkip ]]; then
		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_FSTitle " --yesno "\n$FILESYSTEM $PARTITION\n\n" 0 0
		if [[ $? -eq 0 ]]; then
			${FILESYSTEM} ${PARTITION} >/dev/null 2>/tmp/.errlog
			check_for_error
		else
			select_filesystem
		fi
	fi


 }
  
mount_partitions() {

# This subfunction allows for special mounting options to be applied for relevant fs's.
# Seperate subfunction for neatness.
mount_opts() {

	FS_OPTS=""
	echo "" > ${MOUNT_OPTS}
	
	for i in ${fs_opts}; do
		FS_OPTS="${FS_OPTS} ${i} - off"
	done

	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $(echo $FILESYSTEM | sed "s/.*\.//g" | sed "s/-.*//g") " --checklist "$_btrfsMntBody" 0 0 $CHK_NUM \
	$FS_OPTS 2>${MOUNT_OPTS}
	
	# Now clean up the file
	sed -i 's/ /,/g' ${MOUNT_OPTS}
	sed -i '$s/,$//' ${MOUNT_OPTS}

	# If mount options selected, confirm choice 
	if [[ $(cat ${MOUNT_OPTS}) != "" ]]; then
		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_MntStatusTitle " --yesno "\n${_btrfsMntConfBody}$(cat ${MOUNT_OPTS})\n" 10 75
		[[ $? -eq 1 ]] && mount_opts
	fi 
   
}

# Subfunction to save repetition of code
mount_current_partition(){
	
	# Make the mount directory
	mkdir -p ${MOUNTPOINT}${MOUNT} 2>/tmp/.errlog
	
	# Get mounting options for appropriate filesystems
    [[ $fs_opts != "" ]] && mount_opts
		
	# Use special mounting options if selected, else standard mount
	if [[ $(cat ${MOUNT_OPTS}) != "" ]]; then
		mount -o $(cat ${MOUNT_OPTS}) ${PARTITION} ${MOUNTPOINT}${MOUNT} 2>>/tmp/.errlog
	else
		mount ${PARTITION} ${MOUNTPOINT}${MOUNT} 2>>/tmp/.errlog
	fi
	
	check_for_error
	confirm_mount ${MOUNTPOINT}${MOUNT}

	# Identify if mounted partition is type "crypt" (LUKS on LVM, or LUKS alone)
	if [[ $(lsblk -lno TYPE ${PARTITION} | grep "crypt") != "" ]]; then

        # cryptname for bootloader configuration either way
		LUKS=1
		LUKS_NAME=$(echo ${PARTITION} | sed "s~^/dev/mapper/~~g")

		# Check if LUKS on LVM (parent = lvm /dev/mapper/...) 
		cryptparts=$(lsblk -lno NAME,FSTYPE,TYPE | grep "lvm" | grep -i "crypto_luks" | uniq | awk '{print "/dev/mapper/"$1}')
		for i in ${cryptparts}; do
			if [[ $(lsblk -lno NAME ${i} | grep $LUKS_NAME) != "" ]]; then
				LUKS_DEV="$LUKS_DEV cryptdevice=${i}:$LUKS_NAME"
				LVM=1
				break;
			fi
		done
		
		# Check if LUKS alone (parent = part /dev/...)
		cryptparts=$(lsblk -lno NAME,FSTYPE,TYPE | grep "part" | grep -i "crypto_luks" | uniq | awk '{print "/dev/"$1}')
		for i in ${cryptparts}; do
			if [[ $(lsblk -lno NAME ${i} | grep $LUKS_NAME) != "" ]]; then
				LUKS_UUID=$(lsblk -lno UUID,TYPE,FSTYPE ${i} | grep "part" | grep -i "crypto_luks" | awk '{print $1}')
				LUKS_DEV="$LUKS_DEV cryptdevice=UUID=$LUKS_UUID:$LUKS_NAME"
				break;
			fi
		done
	
	# If LVM logical volume....
	elif [[ $(lsblk -lno TYPE ${PARTITION} | grep "lvm") != "" ]]; then
		LVM=1
		
		# First get crypt name (code above would get lv name)
		cryptparts=$(lsblk -lno NAME,TYPE,FSTYPE | grep "crypt" | grep -i "lvm2_member" | uniq | awk '{print "/dev/mapper/"$1}')
		for i in ${cryptparts}; do
			if [[ $(lsblk -lno NAME ${i} | grep $(echo $PARTITION | sed "s~^/dev/mapper/~~g")) != "" ]]; then
				LUKS_NAME=$(echo ${i} | sed s~/dev/mapper/~~g)
				break;
			fi
		done
		
		# Now get the device (/dev/...) for the crypt name
		cryptparts=$(lsblk -lno NAME,FSTYPE,TYPE | grep "part" | grep -i "crypto_luks" | uniq | awk '{print "/dev/"$1}')
		for i in ${cryptparts}; do
			if [[ $(lsblk -lno NAME ${i} | grep $LUKS_NAME) != "" ]]; then
				# Create UUID for comparison
				LUKS_UUID=$(lsblk -lno UUID,TYPE,FSTYPE ${i} | grep "part" | grep -i "crypto_luks" | awk '{print $1}')
				
				# Check if not already added as a LUKS DEVICE (i.e. multiple LVs on one crypt). If not, add.
				if [[ $(echo $LUKS_DEV | grep $LUKS_UUID) == "" ]]; then
					LUKS_DEV="$LUKS_DEV cryptdevice=UUID=$LUKS_UUID:$LUKS_NAME"
					LUKS=1
				fi
				
				break;
			fi
		done
	fi

	
}

# Seperate function due to ability to cancel
make_swap(){

	# Ask user to select partition or create swapfile
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepMntPart " --menu "$_SelSwpBody" 0 0 7 "$_SelSwpNone" $"-" "$_SelSwpFile" $"-" ${PARTITIONS} 2>${ANSWER} || prep_menu  
    
    if [[ $(cat ${ANSWER}) != "$_SelSwpNone" ]]; then    
       PARTITION=$(cat ${ANSWER})
       
		if [[ $PARTITION == "$_SelSwpFile" ]]; then
			total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2/1024}' | sed 's/\..*//')
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_SelSwpFile " --inputbox "\nM = MB, G = GB\n" 9 30 "${total_memory}M" 2>${ANSWER} || make_swap
			m_or_g=$(cat ${ANSWER})
	
			while [[ $(echo ${m_or_g: -1} | grep "M\|G") == "" ]]; do
				dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_SelSwpFile " --msgbox "\n$_SelSwpFile $_ErrTitle: M = MB, G = GB\n\n" 0 0
				dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_SelSwpFile " --inputbox "\nM = MB, G = GB\n" 9 30 "${total_memory}M" 2>${ANSWER} || make_swap
				m_or_g=$(cat ${ANSWER})
			done

			fallocate -l ${m_or_g} ${MOUNTPOINT}/swapfile 2>/tmp/.errlog
			chmod 600 ${MOUNTPOINT}/swapfile 2>>/tmp/.errlog
			mkswap ${MOUNTPOINT}/swapfile 2>>/tmp/.errlog
			swapon ${MOUNTPOINT}/swapfile 2>>/tmp/.errlog
			check_for_error
			
		else # Swap Partition
			# Warn user if creating a new swap
			if [[ $(lsblk -o FSTYPE  ${PARTITION} | grep -i "swap") != "swap" ]]; then
				dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepMntPart " --yesno "\nmkswap ${PARTITION}\n\n" 0 0
				[[ $? -eq 0 ]] && mkswap ${PARTITION} >/dev/null 2>/tmp/.errlog || mount_partitions
			fi
			# Whether existing to newly created, activate swap
			swapon  ${PARTITION} >/dev/null 2>>/tmp/.errlog
			check_for_error
			# Since a partition was used, remove that partition from the list
			PARTITIONS=$(echo $PARTITIONS | sed "s~${PARTITION} [0-9]*[G-M]~~" | sed "s~${PARTITION} [0-9]*\.[0-9]*[G-M]~~" | sed s~${PARTITION}$' -'~~)
			NUMBER_PARTITIONS=$(( NUMBER_PARTITIONS - 1 ))
		fi
	fi

}
	####								####
	#### MOUNTING FUNCTION BEGINS HERE  ####
	####								####

	# prep variables
	MOUNT=""
	LUKS_NAME=""
	LUKS_DEV=""
	LUKS_UUID=""
	LUKS=0
	LVM=0
	BTRFS=0
	
	# Warn users that they CAN mount partitions without formatting them!
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepMntPart " --msgbox "$_WarnMount1 '$_FSSkip' $_WarnMount2" 0 0

    # LVM Detection. If detected, activate.
    lvm_detect

	# Ensure partitions are unmounted (i.e. where mounted previously), and then list available partitions
	INCLUDE_PART='part\|lvm\|crypt'
    umount_partitions
	find_partitions
	
	# Identify and mount root
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepMntPart " --menu "$_SelRootBody" 0 0 7 ${PARTITIONS} 2>${ANSWER} || prep_menu
	PARTITION=$(cat ${ANSWER})
    ROOT_PART=${PARTITION}
   	
   	# Format with FS (or skip)
	select_filesystem
		
	# Make the directory and mount. Also identify LUKS and/or LVM
	mount_current_partition

	# Identify and create swap, if applicable
	make_swap
	
    # Extra Step for VFAT UEFI Partition. This cannot be in an LVM container.
    if [[ $SYSTEM == "UEFI" ]]; then
    
       dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepMntPart " --menu "$_SelUefiBody" 0 0 7 ${PARTITIONS} 2>${ANSWER} || prep_menu  
       PARTITION=$(cat ${ANSWER})
       UEFI_PART=${PARTITION}
       
       # If it is already a fat/vfat partition...
       if [[ $(fsck -N $PARTITION | grep fat) ]]; then
          dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepMntPart " --yesno "$_FormUefiBody $PARTITION $_FormUefiBody2" 0 0 && mkfs.vfat -F32 ${PARTITION} >/dev/null 2>/tmp/.errlog
       else 
          mkfs.vfat -F32 ${PARTITION} >/dev/null 2>/tmp/.errlog
       fi
       check_for_error
             
       # Inform users of the mountpoint options and consequences       
       dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepMntPart " --menu "$_MntUefiBody"  0 0 2 \
 	   "/boot" "systemd-boot"\
	   "/boot/efi" "-" 2>${ANSWER}
	   	   
	   [[ $(cat ${ANSWER}) != "" ]] && UEFI_MOUNT=$(cat ${ANSWER}) || prep_menu
       
       mkdir -p ${MOUNTPOINT}${UEFI_MOUNT} 2>/tmp/.errlog
       mount ${PARTITION} ${MOUNTPOINT}${UEFI_MOUNT} 2>>/tmp/.errlog
       check_for_error
       confirm_mount ${MOUNTPOINT}${UEFI_MOUNT}           
    fi
    
    # All other partitions
	while [[ $NUMBER_PARTITIONS > 0 ]]; do 
		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepMntPart " --menu "$_ExtPartBody" 0 0 7 "$_Done" $"-" ${PARTITIONS} 2>${ANSWER} || prep_menu 
		PARTITION=$(cat ${ANSWER})
             
		if [[ $PARTITION == $_Done ]]; then
			break;
		else
			MOUNT=""
			select_filesystem
                 
			# Ask user for mountpoint. Don't give /boot as an example for UEFI systems!
			[[ $SYSTEM == "UEFI" ]] && MNT_EXAMPLES="/home\n/var" || MNT_EXAMPLES="/boot\n/home\n/var"
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepMntPart $PARTITON " --inputbox "$_ExtPartBody1$MNT_EXAMPLES\n" 0 0 "/" 2>${ANSWER} || prep_menu
			MOUNT=$(cat ${ANSWER})
                
			# loop while the mountpoint specified is incorrect (is only '/', is blank, or has spaces). 
			while [[ ${MOUNT:0:1} != "/" ]] || [[ ${#MOUNT} -le 1 ]] || [[ $MOUNT =~ \ |\' ]]; do
				# Warn user about naming convention
				dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_ExtErrBody" 0 0
				# Ask user for mountpoint again
				dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepMntPart $PARTITON " --inputbox "$_ExtPartBody1$MNT_EXAMPLES\n" 0 0 "/" 2>${ANSWER} || prep_menu
				MOUNT=$(cat ${ANSWER})                     
			done

			# Create directory and mount.
			mount_current_partition
                
			# Determine if a seperate /boot is used. 0 = no seperate boot, 1 = seperate non-lvm boot, 
			# 2 = seperate lvm boot. For Grub configuration
			if  [[ $MOUNT == "/boot" ]]; then
				[[ $(lsblk -lno TYPE ${PARTITION} | grep "lvm") != "" ]] && LVM_SEP_BOOT=2 || LVM_SEP_BOOT=1
			fi
                
		fi
	done
}	

######################################################################
##																	##
##             Encryption (dm_crypt) Functions				    	##
##																	##
######################################################################

# Had to write it in this way due to (bash?) bug(?), as if/then statements in a single
# "create LUKS" function for default and "advanced" modes were interpreted as commands,
# not mere string statements. Not happy with it, but it works...

# Save repetition of code.
luks_password(){

    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepLUKS " --clear --insecure --passwordbox "$_LuksPassBody" 0 0 2> ${ANSWER} || prep_menu
    PASSWD=$(cat ${ANSWER})
    
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepLUKS " --clear --insecure --passwordbox "$_PassReEntBody" 0 0 2> ${ANSWER} || prep_menu
    PASSWD2=$(cat ${ANSWER})
    
    if [[ $PASSWD != $PASSWD2 ]]; then 
       dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_PassErrBody" 0 0
       luks_password
    fi

}

luks_open(){

	LUKS_ROOT_NAME=""
	INCLUDE_PART='part\|crypt\|lvm'
    umount_partitions
    find_partitions
	
	# Select encrypted partition to open 
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LuksOpen " --menu "$_LuksMenuBody" 0 0 7 ${PARTITIONS} 2>${ANSWER} || luks_menu
	PARTITION=$(cat ${ANSWER})
	
	# Enter name of the Luks partition and get password to open it
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LuksOpen " --inputbox "$_LuksOpenBody" 10 50 "cryptroot" 2>${ANSWER} || luks_menu
    LUKS_ROOT_NAME=$(cat ${ANSWER})
	luks_password
	
	# Try to open the luks partition with the credentials given. If successful show this, otherwise
	# show the error
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LuksOpen " --infobox "$_PlsWaitBody" 0 0
	echo $PASSWD | cryptsetup open --type luks ${PARTITION} ${LUKS_ROOT_NAME} 2>/tmp/.errlog
	check_for_error

	lsblk -o NAME,TYPE,FSTYPE,SIZE,MOUNTPOINT ${PARTITION} | grep "crypt\|NAME\|MODEL\|TYPE\|FSTYPE\|SIZE" > /tmp/.devlist
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_DevShowOpt " --textbox /tmp/.devlist 0 0
	
	luks_menu
}

luks_setup(){

	modprobe -a dm-mod dm_crypt
	INCLUDE_PART='part\|lvm'
    umount_partitions
	find_partitions
	
	# Select partition to encrypt 
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LuksEncrypt " --menu "$_LuksCreateBody" 0 0 7 ${PARTITIONS} 2>${ANSWER} || luks_menu
	PARTITION=$(cat ${ANSWER})

	# Enter name of the Luks partition and get password to create it
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LuksEncrypt " --inputbox "$_LuksOpenBody" 10 50 "cryptroot" 2>${ANSWER} || luks_menu
    LUKS_ROOT_NAME=$(cat ${ANSWER})
    luks_password
}

luks_default() {
	
    # Encrypt selected partition or LV with credentials given
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LuksEncrypt " --infobox "$_PlsWaitBody" 0 0
	sleep 2
	echo $PASSWD | cryptsetup -q luksFormat ${PARTITION} 2>/tmp/.errlog
	
	# Now open the encrypted partition or LV
	echo $PASSWD | cryptsetup open ${PARTITION} ${LUKS_ROOT_NAME} 2>/tmp/.errlog
	check_for_error
	
}

luks_key_define() {
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepLUKS " --inputbox "$_LuksCipherKey" 0 0 "-s 512 -c aes-xts-plain64" 2>${ANSWER} || luks_menu

	# Encrypt selected partition or LV with credentials given
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LuksEncryptAdv " --infobox "$_PlsWaitBody" 0 0
	sleep 2

	echo $PASSWD | cryptsetup -q $(cat ${ANSWER}) luksFormat ${PARTITION} 2>/tmp/.errlog
	check_for_error

	# Now open the encrypted partition or LV
	echo $PASSWD | cryptsetup open ${PARTITION} ${LUKS_ROOT_NAME} 2>/tmp/.errlog
	check_for_error

}

luks_show(){
	
	echo -e ${_LuksEncruptSucc} > /tmp/.devlist
	lsblk -o NAME,TYPE,FSTYPE,SIZE ${PARTITION} | grep "part\|crypt\|NAME\|TYPE\|FSTYPE\|SIZE" >> /tmp/.devlist
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LuksEncrypt " --textbox /tmp/.devlist 0 0

	luks_menu
}

luks_menu() {

	LUKS_OPT=""

	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepLUKS " --menu "$_LuksMenuBody$_LuksMenuBody2$_LuksMenuBody3" 0 0 4 \
	"$_LuksOpen" "cryptsetup open --type luks" \
	"$_LuksEncrypt" "cryptsetup -q luksFormat" \
	"$_LuksEncryptAdv" "cryptsetup -q -s -c luksFormat" \
	"$_Back" "-" 2>${ANSWER}

	case $(cat ${ANSWER}) in
		"$_LuksOpen") 		luks_open ;;
		"$_LuksEncrypt") 	luks_setup
							luks_default
							luks_show ;;
		"$_LuksEncryptAdv")	luks_setup
							luks_key_define
							luks_show ;;
		*) 					prep_menu ;;
	esac

	luks_menu 	

}



######################################################################
##																	##
##             Logical Volume Management Functions			    	##
##																	##
######################################################################

# LVM Detection.
lvm_detect() {
	
  LVM_PV=$(pvs -o pv_name --noheading 2>/dev/null)
  LVM_VG=$(vgs -o vg_name --noheading 2>/dev/null)
  LVM_LV=$(lvs -o vg_name,lv_name --noheading --separator - 2>/dev/null)
  
	if [[ $LVM_LV != "" ]] && [[ $LVM_VG != "" ]] && [[ $LVM_PV != "" ]]; then
		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepLVM " --infobox "$_LvmDetBody" 0 0
		modprobe dm-mod 2>/tmp/.errlog
		check_for_error
		vgscan >/dev/null 2>&1
		vgchange -ay >/dev/null 2>&1
	fi
}

lvm_show_vg(){

	VG_LIST=""
	vg_list=$(lvs --noheadings | awk '{print $2}' | uniq)

	for i in ${vg_list}; do
		VG_LIST="${VG_LIST} ${i} $(vgdisplay ${i} | grep -i "vg size" | awk '{print $3$4}')"
	done

	# If no VGs, no point in continuing
	if [[ $VG_LIST == "" ]]; then
		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_LvmVGErr" 0 0
		lvm_menu
 	fi

	# Select VG
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepLVM " --menu "$_LvmSelVGBody" 0 0 5 \
	${VG_LIST} 2>${ANSWER} || lvm_menu
}

# Create Volume Group and Logical Volumes
lvm_create() {

# subroutine to save a lot of repetition.
check_lv_size() {

	LV_SIZE_INVALID=0
	chars=0

	# Check to see if anything was actually entered and if first character is '0'
	([[ ${#LVM_LV_SIZE} -eq 0 ]] || [[ ${LVM_LV_SIZE:0:1} -eq "0" ]]) && LV_SIZE_INVALID=1

	# If not invalid so far, check for non numberic characters other than the last character
	if [[ $LV_SIZE_INVALID -eq 0 ]]; then
		while [[ $chars -lt $(( ${#LVM_LV_SIZE} - 1 )) ]]; do
			[[ ${LVM_LV_SIZE:chars:1} != [0-9] ]] && LV_SIZE_INVALID=1 && break;
			chars=$(( chars + 1 ))
		done
	fi
	
	# If not invalid so far, check that last character is a M/m or G/g
	if [[ $LV_SIZE_INVALID -eq 0 ]]; then
		LV_SIZE_TYPE=$(echo ${LVM_LV_SIZE:$(( ${#LVM_LV_SIZE} - 1 )):1})
		
		case $LV_SIZE_TYPE in
		"m"|"M"|"g"|"G") LV_SIZE_INVALID=0 ;;
		*) LV_SIZE_INVALID=1 ;;
		esac
		
	fi

	# If not invalid so far, check whether the value is greater than or equal to the LV remaining Size.
	# If not, convert into MB for VG space remaining.      
	if [[ ${LV_SIZE_INVALID} -eq 0 ]]; then
  
		case ${LV_SIZE_TYPE} in
		"G"|"g") if [[ $(( $(echo ${LVM_LV_SIZE:0:$(( ${#LVM_LV_SIZE} - 1 ))}) * 1000 )) -ge ${LVM_VG_MB} ]]; then
					LV_SIZE_INVALID=1
				 else
					LVM_VG_MB=$(( LVM_VG_MB - $(( $(echo ${LVM_LV_SIZE:0:$(( ${#LVM_LV_SIZE} - 1 ))}) * 1000 )) ))
				 fi
				 ;;
		"M"|"m") if [[ $(echo ${LVM_LV_SIZE:0:$(( ${#LVM_LV_SIZE} - 1 ))}) -ge ${LVM_VG_MB} ]]; then
					LV_SIZE_INVALID=1
				 else
					LVM_VG_MB=$(( LVM_VG_MB - $(echo ${LVM_LV_SIZE:0:$(( ${#LVM_LV_SIZE} - 1 ))}) ))
				 fi
				 ;;
		*) LV_SIZE_INVALID=1
				 ;;
		esac

	fi  

}

	#							#
	# LVM Create Starts Here	#
	#							#

	# Prep Variables
	LVM_VG=""
	VG_PARTS=""
	LVM_VG_MB=0

	# Find LVM appropriate partitions.
	INCLUDE_PART='part\|crypt'
	umount_partitions
	find_partitions
    # Amend partition(s) found for use in check list
    PARTITIONS=$(echo $PARTITIONS | sed 's/M\|G\|T/& off/g')
    
    # Name the Volume Group
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG " --inputbox "$_LvmNameVgBody" 0 0 "" 2>${ANSWER} || prep_menu
    LVM_VG=$(cat ${ANSWER})

    # Loop while the Volume Group name starts with a "/", is blank, has spaces, or is already being used
    while [[ ${LVM_VG:0:1} == "/" ]] || [[ ${#LVM_VG} -eq 0 ]] || [[ $LVM_VG =~ \ |\' ]] || [[ $(lsblk | grep ${LVM_VG}) != "" ]]; do
        dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title "$_ErrTitle" --msgbox "$_LvmNameVgErr" 0 0
              
        dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG " --inputbox "$_LvmNameVgBody" 0 0 "" 2>${ANSWER} || prep_menu
        LVM_VG=$(cat ${ANSWER})
    done
    
    # Select the partition(s) for the Volume Group
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG " --checklist "$_LvmPvSelBody $_UseSpaceBar" 0 0 7 ${PARTITIONS} 2>${ANSWER} || prep_menu 
    [[ $(cat ${ANSWER}) != "" ]] && VG_PARTS=$(cat ${ANSWER}) || prep_menu
    
    # Once all the partitions have been selected, show user. On confirmation, use it/them in 'vgcreate' command.
    # Also determine the size of the VG, to use for creating LVs for it.
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG " --yesno "$_LvmPvConfBody1${LVM_VG} $_LvmPvConfBody2${VG_PARTS}" 0 0
    
    if [[ $? -eq 0 ]]; then
       dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG " --infobox "$_LvmPvActBody1${LVM_VG}.$_PlsWaitBody" 0 0
       sleep 1
       vgcreate -f ${LVM_VG} ${VG_PARTS} >/dev/null 2>/tmp/.errlog
       check_for_error
       
		# Once created, get size and size type for display and later number-crunching for lv creation
		VG_SIZE=$(vgdisplay $LV_VG | grep 'VG Size' | awk '{print $3}' | sed 's/\..*//' | sed 's/[^0-9]*//g')
		VG_SIZE_TYPE=$(vgdisplay $LVM_VG | grep 'VG Size' | awk '{print $4}')

		# Convert the VG size into GB and MB. These variables are used to keep tabs on space available and remaining
		[[ ${VG_SIZE_TYPE:0:1} == "G" ]] && LVM_VG_MB=$(( VG_SIZE * 1000 )) || LVM_VG_MB=$VG_SIZE
       
       dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG " --msgbox "$_LvmPvDoneBody1 '${LVM_VG}' $_LvmPvDoneBody2 (${VG_SIZE} ${VG_SIZE_TYPE}).\n\n" 0 0
    else
       lvm_menu
    fi

	#
	# Once VG created, create Logical Volumes
	#
	
	# Specify number of Logical volumes to create.
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG " --radiolist "$_LvmLvNumBody1 ${LVM_VG}. $_LvmLvNumBody2" 0 0 9 \
	"1" "-" off "2" "-" off "3" "-" off "4" "-" off "5" "-" off "6" "-" off "7" "-" off "8" "-" off "9 " "-" off 2>${ANSWER}
    
	[[ $(cat ${ANSWER}) == "" ]] && lvm_menu || NUMBER_LOGICAL_VOLUMES=$(cat ${ANSWER})

	# Loop while the number of LVs is greater than 1. This is because the size of the last LV is automatic.
	while [[ $NUMBER_LOGICAL_VOLUMES -gt 1 ]]; do
		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "$_LvmLvNameBody1" 0 0 "lvol" 2>${ANSWER} || prep_menu
		LVM_LV_NAME=$(cat ${ANSWER})

		# Loop if preceeded with a "/", if nothing is entered, if there is a space, or if that name already exists.
		while [[ ${LVM_LV_NAME:0:1} == "/" ]] || [[ ${#LVM_LV_NAME} -eq 0 ]] || [[ ${LVM_LV_NAME} =~ \ |\' ]] || [[ $(lsblk | grep ${LVM_LV_NAME}) != "" ]]; do
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_LvmLvNameErrBody" 0 0
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "$_LvmLvNameBody1" 0 0 "lvol" 2>${ANSWER} || prep_menu
			LVM_LV_NAME=$(cat ${ANSWER})
		done

		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "\n${LVM_VG}: ${VG_SIZE}${VG_SIZE_TYPE} (${LVM_VG_MB}MB $_LvmLvSizeBody1).$_LvmLvSizeBody2" 0 0 "" 2>${ANSWER} || prep_menu
		LVM_LV_SIZE=$(cat ${ANSWER})          
		check_lv_size 
          
		# Loop while an invalid value is entered.
		while [[ $LV_SIZE_INVALID -eq 1 ]]; do
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_LvmLvSizeErrBody" 0 0
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "\n${LVM_VG}: ${VG_SIZE}${VG_SIZE_TYPE} (${LVM_VG_MB}MB $_LvmLvSizeBody1).$_LvmLvSizeBody2" 0 0 "" 2>${ANSWER} || prep_menu
			LVM_LV_SIZE=$(cat ${ANSWER})          
			check_lv_size
		done
          
		# Create the LV
		lvcreate -L ${LVM_LV_SIZE} ${LVM_VG} -n ${LVM_LV_NAME} 2>/tmp/.errlog
		check_for_error
		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --msgbox "\n$_Done\n\nLV ${LVM_LV_NAME} (${LVM_LV_SIZE}) $_LvmPvDoneBody2.\n\n" 0 0
		NUMBER_LOGICAL_VOLUMES=$(( NUMBER_LOGICAL_VOLUMES - 1 ))
	done
    
	# Now the final LV. Size is automatic.      
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "$_LvmLvNameBody1 $_LvmLvNameBody2 (${LVM_VG_MB}MB)." 0 0 "lvol" 2>${ANSWER} || prep_menu
	LVM_LV_NAME=$(cat ${ANSWER})

	# Loop if preceeded with a "/", if nothing is entered, if there is a space, or if that name already exists.
	while [[ ${LVM_LV_NAME:0:1} == "/" ]] || [[ ${#LVM_LV_NAME} -eq 0 ]] || [[ ${LVM_LV_NAME} =~ \ |\' ]] || [[ $(lsblk | grep ${LVM_LV_NAME}) != "" ]]; do
		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_LvmLvNameErrBody" 0 0
		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "$_LvmLvNameBody1 $_LvmLvNameBody2 (${LVM_VG_MB}MB)." 0 0 "lvol" 2>${ANSWER} || prep_menu
		LVM_LV_NAME=$(cat ${ANSWER})
	done

	# Create the final LV
	lvcreate -l +100%FREE ${LVM_VG} -n ${LVM_LV_NAME} 2>/tmp/.errlog
	check_for_error
	NUMBER_LOGICAL_VOLUMES=$(( NUMBER_LOGICAL_VOLUMES - 1 ))
	LVM=1
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmCreateVG " --yesno "$_LvmCompBody" 0 0 \
	&& show_devices || lvm_menu

}

lvm_del_vg(){

	# Generate list of VGs for selection
	lvm_show_vg
	
	# Ask for confirmation
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmDelVG " --yesno "$_LvmDelQ" 0 0
	
	# if confirmation given, delete
	if [[ $? -eq 0 ]]; then
		vgremove -f $(cat ${ANSWER}) >/dev/null 2>&1
	fi
	
	lvm_menu
}

lvm_del_all(){

	LVM_PV=$(pvs -o pv_name --noheading 2>/dev/null)
	LVM_VG=$(vgs -o vg_name --noheading 2>/dev/null)
	LVM_LV=$(lvs -o vg_name,lv_name --noheading --separator - 2>/dev/null)
	
	# Ask for confirmation
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_LvmDelLV " --yesno "$_LvmDelQ" 0 0
	
	# if confirmation given, delete
	if [[ $? -eq 0 ]]; then
	
		for i in ${LVM_LV}; do
			lvremove -f /dev/mapper/${i} >/dev/null 2>&1
		done

		for i in ${LVM_VG}; do
			vgremove -f ${i} >/dev/null 2>&1
		done

		for i in ${LV_PV}; do
			pvremove -f ${i} >/dev/null 2>&1
		done

	fi
	
	lvm_menu
}

lvm_menu(){

	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepLVM $_PrepLVM2 " --infobox "$_PlsWaitBody" 0 0
	sleep 1
	lvm_detect

	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepLVM $_PrepLVM2 " --menu "$_LvmMenu" 0 0 4 \
	"$_LvmCreateVG" "vgcreate -f, lvcreate -L -n" \
	"$_LvmDelVG" "vgremove -f" \
	"$_LvMDelAll" "lvrmeove, vgremove, pvremove -f" \
	"$_Back" "-" 2>${ANSWER}
	
	case $(cat ${ANSWER}) in
		"$_LvmCreateVG")	lvm_create ;;
		"$_LvmDelVG") 		lvm_del_vg ;;
		"$_LvMDelAll") 		lvm_del_all ;;
		*) 					prep_menu ;;
	esac


}

######################################################################
##																	##
##                    Installation Functions						##
##																	##
######################################################################	

# The linux kernel package will be removed from the base group as it and/or the lts version will be
# selected by the user. Two installation methods are available: Standard (group package based) and
# Advanced (individual package based). Neither will allow progress without selecting a kernel.
install_base() {

	# Prep variables
	echo "" > ${PACKAGES}
	echo "" > ${ANSWER}
	BTRF_CHECK=$(echo "btrfs-progs" "-" off)
	F2FS_CHECK=$(echo "f2fs-tools" "-" off)
	KERNEL="n"
	kernels="linux-lts linux-grsec linux-zen"

	# User to select "standard" or "advanced" installation Method
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstBseTitle " --menu "$_InstBseBody" 0 0 2 \
 	"1" "$_InstStandBase" \
	"2" "$_InstAdvBase" 2>${ANSWER}

	# "Standard" installation method
	if [[ $(cat ${ANSWER}) -eq 1 ]]; then
		
		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstBseTitle " --checklist "$_InstStandBseBody$_UseSpaceBar" 0 0 3 \
		"linux" "-" on \
		"linux-lts" "-" off \
		"base-devel" "-" on 2>${PACKAGES}
	
	# "Advanced" installation method
	elif [[ $(cat ${ANSWER}) -eq 2 ]]; then

		# Ask user to wait while package descriptions are gathered (because it takes ages)
		#dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstAdvBase " --infobox "$_InstAdvWait $_PlsWaitBody" 0 0

		# Generate a package list with descriptions.
		PKG_LIST=""
		pkg_list=$(pacman -Sqg base base-devel | sed s/linux// | sed s/util-/util-linux/ | uniq | sort -u)

		# Check btrfs and f2fs packages in list if used
		[[ $(lsblk -lno FSTYPE | grep btrfs) != "" ]] && BTRF_CHECK=$(echo $BTRFS_CHECK | sed "s/ off/ on/g")
		[[ $(lsblk -lno FSTYPE | grep f2fs) != "" ]] && F2FS_CHECK=$(echo $F2FS_CHECK | sed "s/ off/ on/g")

		# Gather package descriptions for base group
		for i in ${pkg_list}; do
			PKG_LIST="${PKG_LIST} ${i} - on"
		done
		
		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstBseTitle " --checklist "$_InstAdvBseBody $_UseSpaceBar" 0 0 20 \
		"linux" "-" on \
		"linux-lts" "-" off \
		"linux-grsec" "-" off \
		"linux-zen" "-" off \
		$PKG_LIST $BTRF_CHECK $F2FS_CHECK 2>${PACKAGES}
    fi
    
    # If a selection made, act
    if [[ $(cat ${PACKAGES}) != "" ]]; then
    
		# Check to see if a kernel is already installed
		ls ${MOUNTPOINT}/boot/*.img >/dev/null 2>&1
		if [[ $? == 0 ]]; then
			KERNEL="y"
		# If not, check to see if the linux kernel has been selected
		elif [[ $(cat ${PACKAGES} | awk '{print $1}') == "linux" ]]; then
			KERNEL="y"		
		# If no linux kernel, check to see if any of the others have been selected
		else
			for i in ${kernels}; do
				[[ $(cat ${PACKAGES} | grep ${i}) != "" ]] && KERNEL="y" && break;
			done
		fi
		
		# If no kernel selected, warn and restart
		if [[ $KERNEL == "n" ]]; then
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_ErrNoKernel" 0 0
			install_base
		
		# If at least one kernel selected, proceed with installation.
		elif [[ $KERNEL == "y" ]]; then
			clear
			[[ $(cat ${ANSWER}) -eq 1 ]] && pacstrap ${MOUNTPOINT} $(pacman -Sqg base | sed 's/linux//' | sed 's/util-/util-linux/') $(cat ${PACKAGES}) btrfs-progs f2fs-tools sudo 2>/tmp/.errlog
			[[ $(cat ${ANSWER}) -eq 2 ]] && pacstrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
			check_for_error
		
			# If the virtual console has been set, then copy config file to installation
			[[ -e /tmp/vconsole.conf ]] && cp -f /tmp/vconsole.conf ${MOUNTPOINT}/etc/vconsole.conf 2>/tmp/.errlog
			# If specified, copy over the pacman.conf file to the installation
			[[ $COPY_PACCONF -eq 1 ]] && cp -f /etc/pacman.conf ${MOUNTPOINT}/etc/pacman.conf 2>>/tmp/.errlog
			check_for_error
		fi
	fi

}

install_bootloader() {

# Grub auto-detects installed kernels, etc. Syslinux does not, hence the extra code for it.
bios_bootloader() {	
	
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstBiosBtTitle " --menu "$_InstBiosBtBody" 0 0 3 \
 	"grub" "-" "grub + os-prober" "-" "syslinux" "-" 2>${PACKAGES}
	clear
	
	# If something has been selected, act
	if [[ $(cat ${PACKAGES}) != "" ]]; then
		sed -i 's/+\|\"//g' ${PACKAGES}
		pacstrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
		check_for_error
		
		# If Grub, select device
		if [[ $(cat ${PACKAGES} | grep "grub") != "" ]]; then
			select_device
			
			# If a device has been selected, configure
			if [[ $DEVICE != "" ]]; then
				dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " Grub-install " --infobox "$_PlsWaitBody" 0 0
				arch_chroot "grub-install --target=i386-pc --recheck $DEVICE" 2>/tmp/.errlog
				
				# if /boot is LVM (whether using a seperate /boot mount or not), amend grub
				if ( [[ $LVM -eq 1 ]] && [[ $LVM_SEP_BOOT -eq 0 ]] ) || [[ $LVM_SEP_BOOT -eq 2 ]]; then
					sed -i "s/GRUB_PRELOAD_MODULES=\"\"/GRUB_PRELOAD_MODULES=\"lvm\"/g" ${MOUNTPOINT}/etc/default/grub
				fi
				
				# If encryption used amend grub
				[[ $LUKS_DEV != "" ]] && sed -i "s~GRUB_CMDLINE_LINUX=.*~GRUB_CMDLINE_LINUX=\"$LUKS_DEV\"~g" ${MOUNTPOINT}/etc/default/grub
				
				arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg" 2>>/tmp/.errlog
				check_for_error
			fi
		else
			# Syslinux
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstSysTitle " --menu "$_InstSysBody" 0 0 2 \
			"syslinux-install_update -iam" "[MBR]" "syslinux-install_update -i" "[/]" 2>${PACKAGES}
			
			# If an installation method has been chosen, run it
			if [[ $(cat ${PACKAGES}) != "" ]]; then
				arch_chroot "$(cat ${PACKAGES})" 2>/tmp/.errlog
				check_for_error

				# Amend configuration file. First remove all existing entries, then input new ones.	
				sed -i '/^LABEL.*$/,$d' ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				#echo -e "\n" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				
				# First the "main" entries
				[[ -e ${MOUNTPOINT}/boot/initramfs-linux.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Arch Linux\n\tLINUX ../vmlinuz-linux\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				[[ -e ${MOUNTPOINT}/boot/initramfs-linux-lts.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Arch Linux LTS\n\tLINUX ../vmlinuz-linux-lts\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-lts.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				[[ -e ${MOUNTPOINT}/boot/initramfs-linux-grsec.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Arch Linux Grsec\n\tLINUX ../vmlinuz-linux-grsec\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-grsec.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				[[ -e ${MOUNTPOINT}/boot/initramfs-linux-zen.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Arch Linux Zen\n\tLINUX ../vmlinuz-linux-zen\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-zen.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				
				# Second the "fallback" entries
				[[ -e ${MOUNTPOINT}/boot/initramfs-linux.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Arch Linux Fallback\n\tLINUX ../vmlinuz-linux\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-fallback.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				[[ -e ${MOUNTPOINT}/boot/initramfs-linux-lts.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Arch Linux Fallback LTS\n\tLINUX ../vmlinuz-linux-lts\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-lts-fallback.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				[[ -e ${MOUNTPOINT}/boot/initramfs-linux-grsec.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Arch Linux Fallback Grsec\n\tLINUX ../vmlinuz-linux-grsec\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-grsec-fallback.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				[[ -e ${MOUNTPOINT}/boot/initramfs-linux-zen.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Arch Linux Fallbacl Zen\n\tLINUX ../vmlinuz-linux-zen\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-zen-fallback.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				
				# Third, amend for LUKS
				[[ $LUKS_DEV != "" ]] && sed -i "s~rw~$LUKS_DEV rw~g" ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				
				# Finally, re-add the "default" entries
				echo -e "\n\nLABEL hdt\n\tMENU LABEL HDT (Hardware Detection Tool)\n\tCOM32 hdt.c32" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				echo -e "\n\nLABEL reboot\n\tMENU LABEL Reboot\n\tCOM32 reboot.c32" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				echo -e "\n\n#LABEL windows\n\t#MENU LABEL Windows\n\t#COM32 chain.c32\n\t#APPEND root=/dev/sda2 rw" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				echo -e "\n\nLABEL poweroff\n\tMENU LABEL Poweroff\n\tCOM32 poweroff.c32" ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
				
			fi
		fi
	fi
}

uefi_bootloader() {

    #Ensure again that efivarfs is mounted
	[[ -z $(mount | grep /sys/firmware/efi/efivars) ]] && mount -t efivarfs efivarfs /sys/firmware/efi/efivars

    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstUefiBtTitle " --menu "$_InstUefiBtBody" 0 0 2 \
    "grub" "-" "systemd-boot" "/boot" 2>${PACKAGES}

	if [[ $(cat ${PACKAGES}) != "" ]]; then
		
		clear
		pacstrap ${MOUNTPOINT} $(cat ${PACKAGES} | grep -v "systemd-boot") efibootmgr dosfstools 2>/tmp/.errlog
		check_for_error

		case $(cat ${PACKAGES}) in
		"grub") 
				dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " Grub-install " --infobox "$_PlsWaitBody" 0 0
				arch_chroot "grub-install --target=x86_64-efi --efi-directory=${UEFI_MOUNT} --bootloader-id=arch_grub --recheck" 2>/tmp/.errlog
				
				# If encryption used amend grub
				[[ $LUKS_DEV != "" ]] && sed -i "s~GRUB_CMDLINE_LINUX=.*~GRUB_CMDLINE_LINUX=\"$LUKS_DEV\"~g" ${MOUNTPOINT}/etc/default/grub
				
				# Generate config file
				arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg" 2>>/tmp/.errlog
				check_for_error

				# Ask if user wishes to set Grub as the default bootloader and act accordingly
				dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstUefiBtTitle " --yesno "$_SetBootDefBody ${UEFI_MOUNT}/EFI/boot $_SetBootDefBody2" 0 0
			
				if [[ $? -eq 0 ]]; then
					arch_chroot "mkdir ${UEFI_MOUNT}/EFI/boot" 2>/tmp/.errlog
					arch_chroot "cp -r ${UEFI_MOUNT}/EFI/arch_grub/grubx64.efi ${UEFI_MOUNT}/EFI/boot/bootx64.efi" 2>>/tmp/.errlog
					check_for_error
					dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstUefiBtTitle " --infobox "\nGrub $_SetDefDoneBody" 0 0
					sleep 2
				fi
				;;
		"systemd-boot")
				arch_chroot "bootctl --path=${UEFI_MOUNT} install" 2>/tmp/.errlog
				check_for_error
				
				# Deal with LVM Root
				[[ $(echo $ROOT_PART | grep "/dev/mapper/") != "" ]] && bl_root=$ROOT_PART \
				|| bl_root=$"PARTUUID="$(blkid -s PARTUUID ${ROOT_PART} | sed 's/.*=//g' | sed 's/"//g')
 					
				# Create default config files. First the loader
				echo -e "default  arch\ntimeout  10" > ${MOUNTPOINT}${UEFI_MOUNT}/loader/loader.conf 2>/tmp/.errlog
				
				# Second, the kernel conf files
				[[ -e ${MOUNTPOINT}/boot/initramfs-linux.img ]] && echo -e "title\tArch Linux\nlinux\t/vmlinuz-linux\ninitrd\t/initramfs-linux.img\noptions\troot=${bl_root} rw" > ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/arch.conf
				[[ -e ${MOUNTPOINT}/boot/initramfs-linux-lts.img ]] && echo -e "title\tArch Linux LTS\nlinux\t/vmlinuz-linux-lts\ninitrd\t/initramfs-linux-lts.img\noptions\troot=${bl_root} rw" > ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/arch-lts.conf
				[[ -e ${MOUNTPOINT}/boot/initramfs-linux-grsec.img ]] && echo -e "title\tArch Linux Grsec\nlinux\t/vmlinuz-linux-grsec\ninitrd\t/initramfs-linux-grsec.img\noptions\troot=${bl_root} rw" > ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/arch-grsec.conf
				[[ -e ${MOUNTPOINT}/boot/initramfs-linux-zen.img ]] && echo -e "title\tArch Linux Zen\nlinux\t/vmlinuz-linux-zen\ninitrd\t/initramfs-linux-zen.img\noptions\troot=${bl_root} rw" > ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/arch-zen.conf

				# Finally, amend kernel conf files for LUKS and BTRFS
				sysdconf=$(ls ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/arch*.conf)
				for i in ${sysdconf}; do
					[[ $LUKS_DEV != "" ]] && sed -i "s~rw~$LUKS_DEV rw~g" ${i}
				done
				;;
		*) install_base_menu
				;;
		esac
	fi

}
	#									#
	# Bootloader function begins here	#
	#									#
    check_mount
    # Set the default PATH variable
    arch_chroot "PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/core_perl" 2>/tmp/.errlog
    check_for_error

    if [[ $SYSTEM == "BIOS" ]]; then
       bios_bootloader
    else
       uefi_bootloader
    fi
}

# 
install_network_menu() {

# ntp not exactly wireless, but this menu is the best fit.
install_wireless_packages(){

	WIRELESS_PACKAGES=""
	wireless_pkgs="dialog iw rp-pppoe wireless_tools wpa_actiond"
	
	for i in ${wireless_pkgs}; do
		WIRELESS_PACKAGES="${WIRELESS_PACKAGES} ${i} - on"
	done
	
	# If no wireless, uncheck wireless pkgs
	[[ $(lspci | grep -i "Network Controller") == "" ]] && WIRELESS_PACKAGES=$(echo $WIRELESS_PACKAGES | sed "s/ on/ off/g")
	
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstNMMenuPkg " --checklist "$_InstNMMenuPkgBody\n\n$_UseSpaceBar" 0 0 13 \
	$WIRELESS_PACKAGES \
	"ufw" "-" off \
	"gufw" "-" off \
	"ntp" "-" off \
	"b43-fwcutter" "Broadcom 802.11b/g/n" off \
	"bluez-firmware" "Broadcom BCM203x / STLC2300 Bluetooth" off \
	"ipw2100-fw" "Intel PRO/Wireless 2100" off \
	"ipw2200-fw" "Intel PRO/Wireless 2200" off \
	"zd1211-firmware" "ZyDAS ZD1211(b) 802.11a/b/g USB WLAN" off 2>${PACKAGES}
	
	if [[ $(cat ${PACKAGES}) != "" ]]; then
		clear
		pacstrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
		check_for_error
	fi

}

install_cups(){

	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstNMMenuCups " --checklist "$_InstCupsBody\n\n$_UseSpaceBar" 0 0 11 \
	"cups" "-" on \
	"cups-pdf" "-" off \
	"ghostscript" "-" on \
	"gsfonts" "-" on \
	"samba" "-" off 2>${PACKAGES}
	
	if [[ $(cat ${PACKAGES}) != "" ]]; then
		clear
		pacstrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
		check_for_error
		
		if [[ $(cat ${PACKAGES} | grep "cups") != "" ]]; then
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstNMMenuCups " --yesno "$_InstCupsQ" 0 0
			if [[ $? -eq 0 ]]; then
				arch_chroot "systemctl enable org.cups.cupsd.service" 2>/tmp/.errlog
				check_for_error
				dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstNMMenuCups " --infobox "\n$_Done!\n\n" 0 0
				sleep 2
			fi
		fi
	fi
	
}

	if [[ $SUB_MENU != "install_network_packages" ]]; then
	   SUB_MENU="install_network_packages"
	   HIGHLIGHT_SUB=1
	else
	   if [[ $HIGHLIGHT_SUB != 5 ]]; then
	      HIGHLIGHT_SUB=$(( HIGHLIGHT_SUB + 1 ))
	   fi
	fi

    dialog --default-item ${HIGHLIGHT_SUB} --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstNMMenuTitle " --menu "$_InstNMMenuBody" 0 0 5 \
 	"1" "$_SeeWirelessDev" \
 	"2" "$_InstNMMenuPkg" \
 	"3" "$_InstNMMenuNM" \
 	"4" "$_InstNMMenuCups" \
 	"5" "$_Back" 2>${ANSWER}

    case $(cat ${ANSWER}) in
    "1") # Identify the Wireless Device 
        lspci -k | grep -i -A 2 "network controller" > /tmp/.wireless
        if [[ $(cat /tmp/.wireless) != "" ]]; then
           dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_WirelessShowTitle " --textbox /tmp/.wireless 0 0
        else
           dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_WirelessShowTitle " --msgbox "$_WirelessErrBody" 7 30
        fi
        ;;
    "2") install_wireless_packages
        ;;
	"3") install_nm
		;;
	"4") install_cups
		;;
	*) main_menu_online
        ;;
    esac
    
    install_network_menu
   
}

# Install xorg and input drivers. Also copy the xkbmap configuration file created earlier to the installed system
install_xorg_input() {

	echo "" > ${PACKAGES}

	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstGrMenuDS " --checklist "$_InstGrMenuDSBody\n\n$_UseSpaceBar" 0 0 12 \
	"wayland" "-" off \
	"xorg-server" "-" on \
	"xorg-server-common" "-" off \
	"xorg-xinit" "-" on \
	"xorg-server-xwayland" "-" off \
	"xf86-input-evdev" "-" off \
	"xf86-input-joystick" "-" off \
	"xf86-input-keyboard" "-" on \
	"xf86-input-libinput" "-" off \
	"xf86-input-mouse" "-" on \
	"xf86-input-synaptics" "-" on 2>${PACKAGES}

	clear
	# If at least one package, install.
	if [[ $(cat ${PACKAGES}) != "" ]]; then
		pacstrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
		check_for_error
	fi
  
	# now copy across .xinitrc for all user accounts
	user_list=$(ls ${MOUNTPOINT}/home/ | sed "s/lost+found//")
	for i in ${user_list}; do
		cp -f ${MOUNTPOINT}/etc/X11/xinit/xinitrc ${MOUNTPOINT}/home/$i/.xinitrc
		arch_chroot "chown -R ${i}:users /home/${i}"
	done

	install_graphics_menu
}

setup_graphics_card() {

# Save repetition
install_intel(){

	pacstrap ${MOUNTPOINT} xf86-video-intel libva-intel-driver intel-ucode 2>/tmp/.errlog
    sed -i 's/MODULES=""/MODULES="i915"/' ${MOUNTPOINT}/etc/mkinitcpio.conf
           
    # Intel microcode (Grub, Syslinux and systemd-boot).
    # Done as seperate if statements in case of multiple bootloaders.
    if [[ -e ${MOUNTPOINT}/boot/grub/grub.cfg ]]; then
		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " grub-mkconfig " --infobox "$_PlsWaitBody" 0 0
		sleep 1
		arch_chroot "grub-mkconfig -o /boot/grub/grub.cfg" 2>>/tmp/.errlog
	fi

	# Syslinux
	[[ -e ${MOUNTPOINT}/boot/syslinux/syslinux.cfg ]] && sed -i "s/INITRD /&..\/intel-ucode.img,/g" ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
		
	# Systemd-boot
	if [[ -e ${MOUNTPOINT}${UEFI_MOUNT}/loader/loader.conf ]]; then
			update=$(ls ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/*.conf)
			for i in ${upgate}; do
				sed -i '/linux \//a initrd \/intel-ucode.img' ${i}
			done
	fi
			 
}

# Save repetition
install_ati(){
	pacstrap ${MOUNTPOINT} xf86-video-ati 2>/tmp/.errlog
	sed -i 's/MODULES=""/MODULES="radeon"/' ${MOUNTPOINT}/etc/mkinitcpio.conf
}

# Main menu. Correct option for graphics card should be automatically highlighted.
	NVIDIA=""
	VB_MOD=""
	GRAPHIC_CARD=""
	INTEGRATED_GC="N/A"
	GRAPHIC_CARD=$(lspci | grep -i "vga" | sed 's/.*://' | sed 's/(.*//' | sed 's/^[ \t]*//')
	
	# Highlight menu entry depending on GC detected. Extra work is needed for NVIDIA
	if 	[[ $(echo $GRAPHIC_CARD | grep -i "nvidia") != "" ]]; then
		# If NVIDIA, first need to know the integrated GC
		[[ $(lscpu | grep -i "intel\|lenovo") != "" ]] && INTEGRATED_GC="Intel" || INTEGRATED_GC="ATI"
				
		# Second, identity the NVIDIA card and driver / menu entry
		if [[ $(dmesg | grep -i 'chipset' | grep -i 'nvc\|nvd\|nve') != "" ]]; then HIGHLIGHT_SUB_GC=4
		elif [[ $(dmesg | grep -i 'chipset' | grep -i 'nva\|nv5\|nv8\|nv9'﻿) != "" ]]; then HIGHLIGHT_SUB_GC=5
		elif [[ $(dmesg | grep -i 'chipset' | grep -i 'nv4\|nv6') != "" ]]; then HIGHLIGHT_SUB_GC=6
		else HIGHLIGHT_SUB_GC=3
		fi
	
	# All non-NVIDIA cards / virtualisation
	elif [[ $(echo $GRAPHIC_CARD | grep -i 'intel\|lenovo') != "" ]]; then HIGHLIGHT_SUB_GC=2
	elif [[ $(echo $GRAPHIC_CARD | grep -i 'ati') != "" ]]; then HIGHLIGHT_SUB_GC=1
	elif [[ $(echo $GRAPHIC_CARD | grep -i 'via') != "" ]]; then HIGHLIGHT_SUB_GC=7
	elif [[ $(echo $GRAPHIC_CARD | grep -i 'virtualbox') != "" ]]; then HIGHLIGHT_SUB_GC=8
	elif [[ $(echo $GRAPHIC_CARD | grep -i 'vmware') != "" ]]; then HIGHLIGHT_SUB_GC=9
	else HIGHLIGHT_SUB_GC=10
	fi
	
   dialog --default-item ${HIGHLIGHT_SUB_GC} --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_GCtitle " \
    --menu "$GRAPHIC_CARD\n" 0 0 10 \
 	"1" $"xf86-video-ati" \
	"2" $"xf86-video-intel" \
	"3" $"xf86-video-nouveau (+ $INTEGRATED_GC)" \
	"4" $"Nvidia (+ $INTEGRATED_GC)" \
	"5" $"Nvidia-340xx (+ $INTEGRATED_GC)" \
	"6" $"Nvidia-304xx (+ $INTEGRATED_GC)" \
	"7" $"xf86-video-openchrome" \
	"8" $"virtualbox-guest-dkms" \
    "9" $"xf86-video-vmware" \
	"10" "$_GCUnknOpt / xf86-video-fbdev" 2>${ANSWER}

   case $(cat ${ANSWER}) in
        "1") # ATI/AMD
			install_ati
             ;;
        "2") # Intel
			install_intel
             ;;
        "3") # Nouveau / NVIDIA
			[[ $INTEGRATED_GC == "ATI" ]] &&  install_ati || install_intel
			pacstrap ${MOUNTPOINT} xf86-video-nouveau 2>/tmp/.errlog
            sed -i 's/MODULES=""/MODULES="nouveau"/' ${MOUNTPOINT}/etc/mkinitcpio.conf       
             ;;
        "4") # NVIDIA-GF
			[[ $INTEGRATED_GC == "ATI" ]] &&  install_ati || install_intel
			arch_chroot "pacman -Rdds --noconfirm mesa-libgl mesa"
 
 			# Set NVIDIA driver(s) to install depending on installed kernel(s)
			([[ -e ${MOUNTPOINT}/boot/initramfs-linux.img ]] || [[ -e ${MOUNTPOINT}/boot/initramfs-linux-grsec.img ]] || [[ -e ${MOUNTPOINT}/boot/initramfs-linux-zen.img ]]) && NVIDIA="nvidia"
			[[ -e ${MOUNTPOINT}/boot/initramfs-linux-lts.img ]] && NVIDIA="$NVIDIA nvidia-lts"

			clear
			pacstrap ${MOUNTPOINT} ${NVIDIA} nvidia-libgl nvidia-utils pangox-compat nvidia-settings 2>/tmp/.errlog
            NVIDIA_INST=1
             ;;
        "5") # NVIDIA-340

			[[ $INTEGRATED_GC == "ATI" ]] &&  install_ati || install_intel
			arch_chroot "pacman -Rdds --noconfirm mesa-libgl mesa"

			# Set NVIDIA driver(s) to install depending on installed kernel(s)
			([[ -e ${MOUNTPOINT}/boot/initramfs-linux.img ]] || [[ -e ${MOUNTPOINT}/boot/initramfs-linux-grsec.img ]] || [[ -e ${MOUNTPOINT}/boot/initramfs-linux-zen.img ]]) && NVIDIA="nvidia-340xx"
			[[ -e ${MOUNTPOINT}/boot/initramfs-linux-lts.img ]] && NVIDIA="$NVIDIA nvidia-340xx-lts"

			clear
            pacstrap ${MOUNTPOINT} ${NVIDIA} nvidia-340xx-libgl nvidia-340xx-utils nvidia-settings 2>/tmp/.errlog 
            NVIDIA_INST=1
             ;;
        "6") # NVIDIA-304
			[[ $INTEGRATED_GC == "ATI" ]] &&  install_ati || install_intel
			arch_chroot "pacman -Rdds --noconfirm mesa-libgl mesa"
			
  			# Set NVIDIA driver(s) to install depending on installed kernel(s)
  			([[ -e ${MOUNTPOINT}/boot/initramfs-linux.img ]] || [[ -e ${MOUNTPOINT}/boot/initramfs-linux-grsec.img ]] || [[ -e ${MOUNTPOINT}/boot/initramfs-linux-zen.img ]]) && NVIDIA="nvidia-304xx"
			[[ -e ${MOUNTPOINT}/boot/initramfs-linux-lts.img ]] && NVIDIA="$NVIDIA nvidia-304xx-lts"

			clear
            pacstrap ${MOUNTPOINT} ${NVIDIA} nvidia-304xx-libgl nvidia-304xx-utils nvidia-settings 2>/tmp/.errlog
            NVIDIA_INST=1
             ;;              
        "7") # Via
			pacstrap ${MOUNTPOINT} xf86-video-openchrome 2>/tmp/.errlog
             ;;            
        "8") # VirtualBox
        
			# Set VB headers to install depending on installed kernel(s)
			[[ -e ${MOUNTPOINT}/boot/initramfs-linux.img ]] && VB_MOD="linux-headers"
			[[ -e ${MOUNTPOINT}/boot/initramfs-linux-grsec.img ]] && VB_MOD="$VB_MOD linux-grsec-headers"
			[[ -e ${MOUNTPOINT}/boot/initramfs-linux-zen.img ]] && VB_MOD="$VB_MOD linux-zen-headers"
			[[ -e ${MOUNTPOINT}/boot/initramfs-linux-lts.img ]] && VB_MOD="$VB_MOD linux-lts-headers"
        
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title "$_VBoxInstTitle" --msgbox "$_VBoxInstBody" 0 0
            clear
 			
            pacstrap ${MOUNTPOINT} virtualbox-guest-utils virtualbox-guest-dkms $VB_MOD 2>/tmp/.errlog
			umount -l /mnt/dev
 
            # Load modules and enable vboxservice.
            arch_chroot "modprobe -a vboxguest vboxsf vboxvideo"  
            arch_chroot "systemctl enable vboxservice"
            echo -e "vboxguest\nvboxsf\nvboxvideo" > ${MOUNTPOINT}/etc/modules-load.d/virtualbox.conf
             ;;
        "9") # VMWare
			pacstrap ${MOUNTPOINT} xf86-video-vmware xf86-input-vmmouse 2>/tmp/.errlog
             ;;
       "10") # Generic / Unknown
			  pacstrap ${MOUNTPOINT} xf86-video-fbdev 2>/tmp/.errlog
             ;;
          *) install_graphics_menu
             ;;
    esac
    check_for_error

 # Create a basic xorg configuration file for NVIDIA proprietary drivers where installed
 # if that file does not already exist.
 if [[ $NVIDIA_INST == 1 ]] && [[ ! -e ${MOUNTPOINT}/etc/X11/xorg.conf.d/20-nvidia.conf ]]; then
    echo "Section "\"Device"\"" >> ${MOUNTPOINT}/etc/X11/xorg.conf.d/20-nvidia.conf
    echo "        Identifier "\"Nvidia Card"\"" >> ${MOUNTPOINT}/etc/X11/xorg.conf.d/20-nvidia.conf
    echo "        Driver "\"nvidia"\"" >> ${MOUNTPOINT}/etc/X11/xorg.conf.d/20-nvidia.conf
    echo "        VendorName "\"NVIDIA Corporation"\"" >> ${MOUNTPOINT}/etc/X11/xorg.conf.d/20-nvidia.conf
    echo "        Option "\"NoLogo"\" "\"true"\"" >> ${MOUNTPOINT}/etc/X11/xorg.conf.d/20-nvidia.conf
    echo "        #Option "\"UseEDID"\" "\"false"\"" >> ${MOUNTPOINT}/etc/X11/xorg.conf.d/20-nvidia.conf
    echo "        #Option "\"ConnectedMonitor"\" "\"DFP"\"" >> ${MOUNTPOINT}/etc/X11/xorg.conf.d/20-nvidia.conf
    echo "        # ..." >> ${MOUNTPOINT}/etc/X11/xorg.conf.d/20-nvidia.conf
    echo "EndSection" >> ${MOUNTPOINT}/etc/X11/xorg.conf.d/20-nvidia.conf
 fi
 
 # Where NVIDIA has been installed allow user to check and amend the file
 if [[ $NVIDIA_INST == 1 ]]; then
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_NvidiaConfTitle " --msgbox "$_NvidiaConfBody" 0 0
    nano ${MOUNTPOINT}/etc/X11/xorg.conf.d/20-nvidia.conf
 fi
 
 install_graphics_menu

}


install_de_wm() {

   # Only show this information box once
   if [[ $SHOW_ONCE -eq 0 ]]; then
      dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstDETitle " --msgbox "$_DEInfoBody" 0 0
      SHOW_ONCE=1
   fi

	# DE/WM Menu
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstDETitle " --checklist "$_InstDEBody $_UseSpaceBar" 0 0 12 \
	"budgie-desktop" "-" off \
	"cinnamon" "-" off \
	"deepin" "-" off \
	"deepin-extra" "-" off \
	"enlightenment + terminology" "-" off \
	"gnome-shell" "-" off \
	"gnome" "-" off \
	"gnome-extra" "-" off \
	"plasma-desktop" "-" off \
	"plasma" "-" off \
	"kde-applications" "-" off \
	"lxde" "-" off \
	"lxqt + oxygen-icons" "-" off \
	"mate" "-" off \
	"mate-extra" "-" off \
	"mate-gtk3" "-" off \
	"mate-extra-gtk3" "-" off \
	"xfce4" "-" off \
	"xfce4-goodies" "-" off \
	"awesome + vicious" "-" off \
	"fluxbox + fbnews" "-" off \
	"i3-wm + i3lock + i3status" "-" off \
	"icewm + icewm-themes" "-" off \
	"openbox + openbox-themes" "-" off \
	"pekwm + pekwm-themes" "-" off \
	"windowmaker" "-" off 2>${PACKAGES}

	# If something has been selected, install
	if [[ $(cat ${PACKAGES}) != "" ]]; then
		clear
		sed -i 's/+\|\"//g' ${PACKAGES}
		pacstrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
		check_for_error

		
		# Clear the packages file for installation of "common" packages
		echo "" > ${PACKAGES}

		# Offer to install various "common" packages.
		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstComTitle " --checklist "$_InstComBody $_UseSpaceBar" 0 50 14 \
		"bash-completion" "-" on \
		"gamin" "-" on \
		"gnome-icon-theme" "-" on \
		"gnome-keyring" "-" on \
		"gvfs" "-" on \
		"gvfs-afc" "-" on \
		"gvfs-smb" "-" on \
		"polkit" "-" on \
		"poppler" "-" on \
		"python2-xdg" "-" on \
		"ntfs-3g" "-" on \
		"ttf-dejavu" "-" on \
		"xdg-user-dirs" "-" on \
		"xdg-utils" "-" on \
		"xterm" "-" on 2>${PACKAGES}

		# If at least one package, install.
		if [[ $(cat ${PACKAGES}) != "" ]]; then
			clear
			pacstrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
			check_for_error
		fi

	fi

}

# Display Manager
install_dm() {

# Save repetition of code
enable_dm() {
	arch_chroot "systemctl enable $(cat ${PACKAGES})" 2>/tmp/.errlog
	check_for_error
	DM=$(cat ${PACKAGES})
	DM_ENABLED=1
}

	if [[ $DM_ENABLED -eq 0 ]]; then
		# Prep variables
		echo "" > ${PACKAGES}
		dm_list="gdm lxdm lightdm sddm"
		DM_LIST=""
		DM_INST=""

		# Generate list of DMs installed with DEs, and a list for selection menu
		for i in ${dm_list}; do
			[[ -e ${MOUNTPOINT}/usr/bin/${i} ]] && DM_INST="${DM_INST} ${i}"
			DM_LIST="${DM_LIST} ${i} -"
		done

		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_DmChTitle " --menu "$_AlreadyInst$DM_INST\n\n$_DmChBody" 0 0 4 \
		${DM_LIST} 2>${PACKAGES}
		clear
		
		# If a selection has been made, act
		if [[ $(cat ${PACKAGES}) != "" ]]; then
		
			# check if selected dm already installed. If so, enable and break loop.
			for i in ${DM_INST}; do
				if [[ $(cat ${PACKAGES}) == ${i} ]]; then
					enable_dm
					break;
				fi
			done
		
			# If no match found, install and enable DM	
			if [[ $DM_ENABLED -eq 0 ]]; then
		
				# Where lightdm selected, add gtk greeter package
				sed -i 's/lightdm/lightdm lightdm-gtk-greeter/' ${PACKAGES}
				pacstrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
				
				# Where lightdm selected, now remove the greeter package
				sed -i 's/lightdm-gtk-greeter//' ${PACKAGES}
				enable_dm
			fi
		fi
	fi

	# Show after successfully installing or where attempting to repeat when already completed.
	[[ $DM_ENABLED -eq 1 ]] && dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_DmChTitle " --msgbox "$_DmDoneBody" 0 0       

}

# Network Manager
install_nm() {

# Save repetition of code
enable_nm() {
	if [[ $(cat ${PACKAGES}) == "NetworkManager" ]]; then
		arch_chroot "systemctl enable NetworkManager.service && systemctl enable NetworkManager-dispatcher.service" >/tmp/.symlink 2>/tmp/.errlog
	else
		arch_chroot "systemctl enable $(cat ${PACKAGES})" 2>/tmp/.errlog
	fi
	
	check_for_error
	NM_ENABLED=1
}

	if [[ $NM_ENABLED -eq 0 ]]; then
		# Prep variables
		echo "" > ${PACKAGES}
		nm_list="connman CLI dhcpcd CLI netctl CLI NetworkManager GUI wicd GUI"
		NM_LIST=""
		NM_INST=""

		# Generate list of DMs installed with DEs, and a list for selection menu
		for i in ${nm_list}; do
			[[ -e ${MOUNTPOINT}/usr/bin/${i} ]] && NM_INST="${NM_INST} ${i}"
			NM_LIST="${NM_LIST} ${i}"
		done

		# Remove netctl from selectable list as it is a PITA to configure via arch_chroot
		NM_LIST=$(echo $NM_LIST | sed "s/netctl CLI//")

		dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstNMTitle " --menu "$_AlreadyInst $NM_INST\n$_InstNMBody" 0 0 4 \
		${NM_LIST} 2> ${PACKAGES}
		clear

		# If a selection has been made, act
		if [[ $(cat ${PACKAGES}) != "" ]]; then
		
			# check if selected nm already installed. If so, enable and break loop.
			for i in ${NM_INST}; do
				[[ $(cat ${PACKAGES}) == ${i} ]] && enable_nm && break
			done
			            
			# If no match found, install and enable NM	
			if [[ $NM_ENABLED -eq 0 ]]; then
			 
				# Where networkmanager selected, add network-manager-applet
				sed -i 's/NetworkManager/networkmanager network-manager-applet/g' ${PACKAGES}
				pacstrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
			
				# Where networkmanager selected, now remove network-manager-applet
				sed -i 's/networkmanager network-manager-applet/NetworkManager/g' ${PACKAGES}
				enable_nm
			fi
		fi
	fi
	
	# Show after successfully installing or where attempting to repeat when already completed.
	[[ $NM_ENABLED -eq 1 ]] && dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstNMTitle " --msgbox "$_InstNMErrBody" 0 0


}

install_multimedia_menu(){

install_alsa_pulse(){
	# Prep Variables
	echo "" > ${PACKAGES}
	ALSA=""
	PULSE_EXTRA=""
	alsa=$(pacman -Ss alsa | awk '{print $1}' | grep "/alsa-" | sed "s/extra\///g" | sort -u)
	pulse_extra=$(pacman -Ss pulseaudio- | awk '{print $1}' | sed "s/extra\///g" | grep "pulseaudio-" | sort -u)
	
	for i in ${alsa}; do
		ALSA="${ALSA} ${i} - off"
	done
	
	ALSA=$(echo $ALSA | sed "s/alsa-utils - off/alsa-utils - on/g" | sed "s/alsa-plugins - off/alsa-plugins - on/g")

	for i in ${pulse_extra}; do
		PULSE_EXTRA="${PULSE_EXTRA} ${i} - off"
	done

	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstMulSnd " --checklist "$_InstMulSndBody\n\n$_UseSpaceBar" 0 0 14 \
	$ALSA "pulseaudio" "-" off $PULSE_EXTRA \
	"paprefs" "pulseaudio GUI" off \
	"pavucontrol" "pulseaudio GUI" off \
	"ponymix" "pulseaudio CLI" off \
	"volumeicon" "ALSA GUI" off \
	"volwheel" "ASLA GUI" off 2>${PACKAGES}

	clear
	# If at least one package, install.
	if [[ $(cat ${PACKAGES}) != "" ]]; then
		pacstrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
		check_for_error
	fi

}

install_codecs(){

	# Prep Variables
	echo "" > ${PACKAGES}
	GSTREAMER=""
	gstreamer=$(pacman -Ss gstreamer | awk '{print $1}' | grep "/gstreamer" | sed "s/extra\///g" | sed "s/community\///g" | sort -u)
	echo $gstreamer
	for i in ${gstreamer}; do
		GSTREAMER="${GSTREAMER} ${i} - off"
	done

	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstMulCodec " --checklist "$_InstMulCodBody$_UseSpaceBar" 0 0 14 \
	$GSTREAMER "xine-lib" "-" off 2>${PACKAGES}

	# If at least one package, install.
	if [[ $(cat ${PACKAGES}) != "" ]]; then
		pacstrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
		check_for_error
	fi
	
}
 
install_cust_pkgs(){
	echo "" > ${PACKAGES}
	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstMulCust " --inputbox "$_InstMulCustBody" 0 0 "" 2>${PACKAGES} || install_multimedia_menu

	clear
	# If at least one package, install.
	if [[ $(cat ${PACKAGES}) != "" ]]; then
		if [[ $(cat ${PACKAGES}) == "hen poem" ]]; then
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " \"My Sweet Buckies\" by Atiya & Carl " --msgbox "\nMy Sweet Buckies,\nYou are the sweetest Buckies that ever did \"buck\",\nLily, Rosie, Trumpet, and Flute,\nMy love for you all is absolute!\n\nThey buck: \"We love our treats, we are the Booyakka sisters,\"\n\"Sometimes we squabble and give each other comb-twisters,\"\n\"And in our garden we love to sunbathe, forage, hop and jump,\"\n\"We love our freedom far, far away from that factory farm dump,\"\n\n\"For so long we were trapped in cramped prisons full of disease,\"\n\"No sunlight, no fresh air, no one who cared for even our basic needs,\"\n\"We suffered in fear, pain, and misery for such a long time,\"\n\"But now we are so happy, we wanted to tell you in this rhyme!\"\n\n" 0 0
		else
			pacstrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>/tmp/.errlog
			check_for_error
		fi
	fi
	
}

	if [[ $SUB_MENU != "install_multimedia_menu" ]]; then
	   SUB_MENU="install_multimedia_menu"
	   HIGHLIGHT_SUB=1
	else
	   if [[ $HIGHLIGHT_SUB != 5 ]]; then
	      HIGHLIGHT_SUB=$(( HIGHLIGHT_SUB + 1 ))
	   fi
	fi

    dialog --default-item ${HIGHLIGHT_SUB} --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstMultMenuTitle " --menu "$_InstMultMenuBody" 0 0 5 \
 	"1" "$_InstMulSnd" \
 	"2" "$_InstMulCodec" \
 	"3" "$_InstMulAcc" \
 	"4" "$_InstMulCust" \
 	"5" "$_Back" 2>${ANSWER}
 	
	HIGHLIGHT_SUB=$(cat ${ANSWER})
	case $(cat ${ANSWER}) in
        "1") install_alsa_pulse
             ;;
        "2") install_codecs
             ;;
        "3") install_acc_menu
             ;;
        "4") install_cust_pkgs
             ;;
		  *) main_menu_online
             ;;
	esac
	
	install_multimedia_menu
}

security_menu(){

	if [[ $SUB_MENU != "security_menu" ]]; then
	   SUB_MENU="security_menu"
	   HIGHLIGHT_SUB=1
	else
	   if [[ $HIGHLIGHT_SUB != 4 ]]; then
	      HIGHLIGHT_SUB=$(( HIGHLIGHT_SUB + 1 ))
	   fi
	fi

    dialog --default-item ${HIGHLIGHT_SUB} --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_SecMenuTitle " --menu "$_SecMenuBody" 0 0 4 \
 	"1" "$_SecJournTitle" \
	"2" "$_SecCoreTitle" \
	"3" "$_SecKernTitle" \
	"4" "$_Back" 2>${ANSWER}

	HIGHLIGHT_SUB=$(cat ${ANSWER})
	case $(cat ${ANSWER}) in
        "1") # systemd-journald
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_SecJournTitle " --menu "$_SecJournBody" 0 0 7 \
			"$_Edit" "/etc/systemd/journald.conf" \
			"10M" "SystemMaxUse=10M" \
			"20M" "SystemMaxUse=20M" \
			"50M" "SystemMaxUse=50M" \
			"100M" "SystemMaxUse=100M" \
			"200M" "SystemMaxUse=200M" \
			"$_Disable" "Storage=none" 2>${ANSWER}

			if [[ $(cat ${ANSWER}) != "" ]]; then
				if  [[ $(cat ${ANSWER}) == "$_Disable" ]]; then
					sed -i "s/#Storage.*\|Storage.*/Storage=none/g" ${MOUNTPOINT}/etc/systemd/journald.conf
					sed -i "s/SystemMaxUse.*/#&/g" ${MOUNTPOINT}/etc/systemd/journald.conf
					dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_SecJournTitle " --infobox "\n$_Done!\n\n" 0 0
					sleep 2
				elif [[ $(cat ${ANSWER}) == "$_Edit" ]]; then
					nano ${MOUNTPOINT}/etc/systemd/journald.conf
				else
					sed -i "s/#SystemMaxUse.*\|SystemMaxUse.*/SystemMaxUse=$(cat ${ANSWER})/g" ${MOUNTPOINT}/etc/systemd/journald.conf
					sed -i "s/Storage.*/#&/g" ${MOUNTPOINT}/etc/systemd/journald.conf
					dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_SecJournTitle " --infobox "\n$_Done!\n\n" 0 0
					sleep 2
				fi
			fi
			;;
		"2") # core dump
			 dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_SecCoreTitle " --menu "$_SecCoreBody" 0 0 2 \
			"$_Disable" "Storage=none" "$_Edit" "/etc/systemd/coredump.conf" 2>${ANSWER}
			
			if [[ $(cat ${ANSWER}) == "$_Disable" ]]; then
				sed -i "s/#Storage.*\|Storage.*/Storage=none/g" ${MOUNTPOINT}/etc/systemd/coredump.conf
				dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_SecCoreTitle " --infobox "\n$_Done!\n\n" 0 0
				sleep 2
			elif [[ $(cat ${ANSWER}) == "$_Edit" ]]; then
				nano ${MOUNTPOINT}/etc/systemd/coredump.conf
			fi
          ;;
        "3") # Kernel log access 
			dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_SecKernTitle " --menu "\nKernel logs may contain information an attacker can use to identify and exploit kernel vulnerabilities, including sensitive memory addresses.\n\nIf systemd-journald logging has not been disabled, it is possible to create a rule in /etc/sysctl.d/ to disable access to these logs unless using root privilages (e.g. via sudo).\n" 0 0 2 \
			"$_Disable" "kernel.dmesg_restrict = 1" "$_Edit" "/etc/systemd/coredump.conf.d/custom.conf" 2>${ANSWER}
			
			case $(cat ${ANSWER}) in
			"$_Disable") 	echo "kernel.dmesg_restrict = 1" > ${MOUNTPOINT}/etc/sysctl.d/50-dmesg-restrict.conf
							dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_SecKernTitle " --infobox "\n$_Done!\n\n" 0 0
							sleep 2 ;;
			"$_Edit") 		[[ -e ${MOUNTPOINT}/etc/sysctl.d/50-dmesg-restrict.conf ]] && nano ${MOUNTPOINT}/etc/sysctl.d/50-dmesg-restrict.conf \
							|| dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_SeeConfErrTitle " --msgbox "$_SeeConfErrBody1" 0 0 ;;
			esac
             ;;
          *) main_menu_online
			;;
    esac
    
    security_menu
}

######################################################################
##																	##
##                 Main Interfaces       							##
##																	##
######################################################################

# Greet the user when first starting the installer
greeting() {

dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_WelTitle $VERSION " --msgbox "$_WelBody" 0 0	

}

# Preparation
prep_menu() {
	
	if [[ $SUB_MENU != "prep_menu" ]]; then
	   SUB_MENU="prep_menu"
	   HIGHLIGHT_SUB=1
	else
	   if [[ $HIGHLIGHT_SUB != 7 ]]; then
	      HIGHLIGHT_SUB=$(( HIGHLIGHT_SUB + 1 ))
	   fi
	fi
	
	dialog --default-item ${HIGHLIGHT_SUB} --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_PrepMenuTitle " --menu "$_PrepMenuBody" 0 0 7 \
	"1" "$_VCKeymapTitle" \
	"2" "$_DevShowOpt" \
	"3" "$_PrepPartDisk" \
	"4" "$_PrepLUKS" \
	"5" "$_PrepLVM $_PrepLVM2" \
	"6" "$_PrepMntPart" \
	"7" "$_Back" 2>${ANSWER}

    HIGHLIGHT_SUB=$(cat ${ANSWER})
	case $(cat ${ANSWER}) in
        "1") set_keymap 
             ;;
        "2") show_devices
             ;;
        "3") umount_partitions
             select_device
             create_partitions
             ;;
        "4") luks_menu
			;;
        "5") lvm_menu
             ;;
        "6") mount_partitions
             ;;        
          *) main_menu_online
             ;;
    esac
    
    prep_menu  	
	
}

# Base Installation
install_base_menu() {

	if [[ $SUB_MENU != "install_base_menu" ]]; then
	   SUB_MENU="install_base_menu"
	   HIGHLIGHT_SUB=1
	else
	   if [[ $HIGHLIGHT_SUB != 5 ]]; then
	      HIGHLIGHT_SUB=$(( HIGHLIGHT_SUB + 1 ))
	   fi
	fi

   dialog --default-item ${HIGHLIGHT_SUB} --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstBsMenuTitle " --menu "$_InstBseMenuBody" 0 0 5 \
 	"1"	"$_PrepMirror" \
 	"2" "$_PrepPacKey" \
 	"3" "$_PrepPacKey MIT keyserver" \
 	"4" "$_InstBse" \
	"5" "$_InstBootldr" \
	"6" "$_Back" 2>${ANSWER}	
	
	HIGHLIGHT_SUB=$(cat ${ANSWER})
	case $(cat ${ANSWER}) in
	"1") configure_mirrorlist
		;;
	"2") clear
		 pacman-key --init
		 pacman-key --populate archlinux
		 pacman-key --refresh-keys
		;;
	"3") clear
		 pacman-key --init
		 pacman-key --populate archlinux
		 pacman-key --refresh-keys --keyserver http://pgp.mit.edu
		;;
	"4") install_base
		;;
	"5") install_bootloader
		;;
	*) main_menu_online
		;;
	esac
    
	install_base_menu 	
}

# Base Configuration
config_base_menu() {
	
	# Set the default PATH variable
    arch_chroot "PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/bin/core_perl" 2>/tmp/.errlog
	check_for_error
	
	if [[ $SUB_MENU != "config_base_menu" ]]; then
	   SUB_MENU="config_base_menu"
	   HIGHLIGHT_SUB=1
	else
	   if [[ $HIGHLIGHT_SUB != 8 ]]; then
	      HIGHLIGHT_SUB=$(( HIGHLIGHT_SUB + 1 ))
	   fi
	fi

    dialog --default-item ${HIGHLIGHT_SUB} --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ConfBseMenuTitle " --menu "$_ConfBseBody" 0 0 8 \
 	"1" "$_ConfBseFstab" \
	"2" "$_ConfBseHost" \
	"3" "$_ConfBseSysLoc" \
	"4" "$_ConfBseTimeHC" \
	"5" "$_ConfUsrRoot" \
	"6" "$_ConfUsrNew" \
	"7" "$_MMRunMkinit" \
	"8" "$_Back" 2>${ANSWER}	
	
	HIGHLIGHT_SUB=$(cat ${ANSWER})
	case $(cat ${ANSWER}) in
        "1") generate_fstab 
             ;;
        "2") set_hostname
             ;;
        "3") set_locale
             ;;        
        "4") set_timezone
			 set_hw_clock
             ;;
		"5") set_root_password 
			;;
		"6") create_new_user
			;;
		"7") run_mkinitcpio
			;;
          *) main_menu_online
			;;
    esac
    
    config_base_menu

}

install_graphics_menu() {

	if [[ $SUB_MENU != "install_graphics_menu" ]]; then
	   SUB_MENU="install_graphics_menu"
	   HIGHLIGHT_SUB=1
	else
	   if [[ $HIGHLIGHT_SUB != 6 ]]; then
	      HIGHLIGHT_SUB=$(( HIGHLIGHT_SUB + 1 ))
	   fi
	fi

    dialog --default-item ${HIGHLIGHT_SUB} --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstGrMenuTitle " --menu "$_InstGrMenuBody" 0 0 6 \
 	"1" "$_InstGrMenuDS" \
	"2" "$_InstGrMenuDD" \
	"3" "$_InstGrMenuGE" \
	"4" "$_InstGrMenuDM" \
	"5"	"$_PrepKBLayout" \
	"6" "$_Back" 2>${ANSWER}

	HIGHLIGHT_SUB=$(cat ${ANSWER})
	case $(cat ${ANSWER}) in
        "1") install_xorg_input
			;;
		"2") setup_graphics_card 
             ;;
        "3") install_de_wm
             ;;
        "4") install_dm
             ;;
		"5") set_xkbmap
			;;
          *) main_menu_online
			;;
    esac
    
    install_graphics_menu
   
}

# Install Accessibility Applications
install_acc_menu() {

	echo "" > ${PACKAGES}

	dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_InstAccTitle " --checklist "$_InstAccBody" 0 0 15 \
	"accerciser" "-" off \
	"at-spi2-atk" "-" off \
	"at-spi2-core" "-" off \
	"brltty" "-" off \
	"caribou" "-" off \
	"dasher" "-" off \
	"espeak" "-" off \
	"espeakup" "-" off \
	"festival" "-" off \
	"java-access-bridge" "-" off \
	"java-atk-wrapper" "-" off \
	"julius" "-" off \
	"orca" "-" off \
	"qt-at-spi" "-" off \
	"speech-dispatcher" "-" off 2>${PACKAGES}
	
	clear
	# If something has been selected, install
	if [[ $(cat ${PACKAGES}) != "" ]]; then
		pacstrap ${MOUNTPOINT} ${PACKAGES} 2>/tmp/.errlog
		check_for_error
	fi
	
	install_multimedia_menu

}


edit_configs() {
	
	# Clear the file variables
	FILE=""
	user_list=""
	
	if [[ $SUB_MENU != "edit configs" ]]; then
	   SUB_MENU="edit configs"
	   HIGHLIGHT_SUB=1
	else
	   if [[ $HIGHLIGHT_SUB != 12 ]]; then
	      HIGHLIGHT_SUB=$(( HIGHLIGHT_SUB + 1 ))
	   fi
	fi

   dialog --default-item ${HIGHLIGHT_SUB} --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_SeeConfOptTitle " --menu "$_SeeConfOptBody" 0 0 13 \
   "1" "/etc/vconsole.conf" \
   "2" "/etc/locale.conf" \
   "3" "/etc/hostname" \
   "4" "/etc/hosts" \
   "5" "/etc/sudoers" \
   "6" "/etc/mkinitcpio.conf" \
   "7" "/etc/fstab" \
   "8" "/etc/crypttab" \
   "9" "grub/syslinux/systemd-boot" \
   "10" "lxdm/lightdm/sddm" \
   "11" "/etc/pacman.conf" \
   "12" "~/.xinitrc" \
   "13" "$_Back" 2>${ANSWER}
	
	HIGHLIGHT_SUB=$(cat ${ANSWER})
	case $(cat ${ANSWER}) in
	    "1") [[ -e ${MOUNTPOINT}/etc/vconsole.conf ]] && FILE="${MOUNTPOINT}/etc/vconsole.conf"
             ;;
        "2") [[ -e ${MOUNTPOINT}/etc/locale.conf ]] && FILE="${MOUNTPOINT}/etc/locale.conf" 
             ;;
        "3") [[ -e ${MOUNTPOINT}/etc/hostname ]] && FILE="${MOUNTPOINT}/etc/hostname"
             ;;
        "4") [[ -e ${MOUNTPOINT}/etc/hosts ]] && FILE="${MOUNTPOINT}/etc/hosts"
             ;;
        "5") [[ -e ${MOUNTPOINT}/etc/sudoers ]] && FILE="${MOUNTPOINT}/etc/sudoers"
             ;;
        "6") [[ -e ${MOUNTPOINT}/etc/mkinitcpio.conf ]] && FILE="${MOUNTPOINT}/etc/mkinitcpio.conf"
             ;;
        "7") [[ -e ${MOUNTPOINT}/etc/fstab ]] && FILE="${MOUNTPOINT}/etc/fstab"
             ;;
        "8") [[ -e ${MOUNTPOINT}/etc/crypttab ]] && FILE="${MOUNTPOINT}/etc/crypttab"
			 ;;
        "9") [[ -e ${MOUNTPOINT}/etc/default/grub ]] && FILE="${MOUNTPOINT}/etc/default/grub"
			 [[ -e ${MOUNTPOINT}/boot/syslinux/syslinux.cfg ]] && FILE="$FILE ${MOUNTPOINT}/boot/syslinux/syslinux.cfg"
			 if [[ -e ${MOUNTPOINT}${UEFI_MOUNT}/loader/loader.conf ]]; then
				files=$(ls ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/*.conf)
				for i in ${files}; do
					FILE="$FILE ${i}"
				done
			 fi
            ;;
        "10") [[ -e ${MOUNTPOINT}/etc/lxdm/lxdm.conf ]] && FILE="${MOUNTPOINT}/etc/lxdm/lxdm.conf" 
			  [[ -e ${MOUNTPOINT}/etc/lightdm/lightdm.conf ]] && FILE="${MOUNTPOINT}/etc/lightdm/lightdm.conf"
              [[ -e ${MOUNTPOINT}/etc/sddm.conf ]] && FILE="${MOUNTPOINT}/etc/sddm.conf"
            ;;
        "11") [[ -e ${MOUNTPOINT}/etc/pacman.conf ]] && FILE="${MOUNTPOINT}/etc/pacman.conf"
			;;
		"12") user_list=$(ls ${MOUNTPOINT}/home/ | sed "s/lost+found//")
			  for i in ${user_list}; do
				[[ -e ${MOUNTPOINT}/home/$i/.xinitrc ]] && FILE="$FILE ${MOUNTPOINT}/home/$i/.xinitrc"
			  done
			;;
         *) main_menu_online
            ;;
     esac
     
	[[ $FILE != "" ]] && nano $FILE \
	|| dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_ErrTitle " --msgbox "$_SeeConfErrBody" 0 0
	
	edit_configs
}

main_menu_online() {
	
	if [[ $HIGHLIGHT != 9 ]]; then
	   HIGHLIGHT=$(( HIGHLIGHT + 1 ))
	fi
	
    dialog --default-item ${HIGHLIGHT} --backtitle "$VERSION - $SYSTEM ($ARCHI)" --title " $_MMTitle " \
    --menu "$_MMBody" 0 0 9 \
 	"1" "$_PrepMenuTitle" \
	"2" "$_InstBsMenuTitle" \
	"3" "$_ConfBseMenuTitle" \
	"4" "$_InstGrMenuTitle" \
	"5" "$_InstNMMenuTitle" \
    "6" "$_InstMultMenuTitle" \
    "7" "$_SecMenuTitle" \
    "8" "$_SeeConfOptTitle" \
	"9" "$_Done" 2>${ANSWER}

    HIGHLIGHT=$(cat ${ANSWER})
    
    # Depending on the answer, first check whether partition(s) are mounted and whether base has been installed
    if [[ $(cat ${ANSWER}) -eq 2 ]]; then
       check_mount
    fi

    if [[ $(cat ${ANSWER}) -ge 3 ]] && [[ $(cat ${ANSWER}) -le 8 ]]; then
       check_mount
       check_base
    fi
    
    case $(cat ${ANSWER}) in
        "1") prep_menu 
             ;;
        "2") install_base_menu
             ;;
        "3") config_base_menu
             ;;          
        "4") install_graphics_menu
             ;;
        "5") install_network_menu
			;;
        "6") install_multimedia_menu
			;;
        "7") security_menu
			;;
        "8") edit_configs
             ;;            
          *) dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --yesno "$_CloseInstBody" 0 0
          
             if [[ $? -eq 0 ]]; then
                umount_partitions
                clear
                exit 0
             else
                main_menu_online
             fi
             
             ;;
    esac
    
    main_menu_online 
    
}

######################################################################
##																	##
##                        Execution     							##
##																	##
######################################################################
id_system
select_language
check_requirements
greeting

	while true; do
          main_menu_online      
    done
