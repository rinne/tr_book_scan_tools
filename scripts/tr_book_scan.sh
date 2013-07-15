#! /bin/bash

export LANG=C
PTPCAM='/opt/diybookscanner/bin/ptpcam'
GPHOTO2='/usr/bin/gphoto2'
ZOOMLVL=18
TMOUT=15
TMOUT2=2

CAMERA_DELAY_SHORT=1.0
CAMERA_DELAY_FULL=2.0

function local_file_name {
  printf "%s/pg-%04d.jpg" "$(pwd)" $PHOTOCOUNTER
}

if test $# -eq 0 ; then
  PHOTOCOUNTER=0
  while test -e "$(local_file_name)" ; do
    PHOTOCOUNTER=$(expr $PHOTOCOUNTER + 1)
  done
elif test $# -eq 1 && echo "$1" | grep -E '^[1-9][0-9]?[0-9]?[0-9]?[0-9]?$' >/dev/null ; then
  PHOTOCOUNTER="$1"
else
  echo "Usage $0 [ last-successfully-scanned--page-number ]" 1>&2
  exit 1
fi

if test $PHOTOCOUNTER -eq 0 ; then
  echo "Directory seems to be clear. Starting from the first page."
else
  echo "Starting AFTER the page $PHOTOCOUNTER"
  if test -e "$(local_file_name)" ; then
    echo "+-----------------------------------------------------------------+"
    echo "|                                                                 |"
    echo "| WARNING: Existing files will be overwritten by this start page. |" 
    echo "|                                                                 |"
    echo "+-----------------------------------------------------------------+"
  fi
fi

function camera_delay_short {
  sleep $CAMERA_DELAY_SHORT
}

function camera_delay_full {
  sleep $CAMERA_DELAY_FULL
}

function forget_cams {
  RIGHTCAM=''
  LEFTCAM=''
  RIGHTCAMLONG=''
  LEFTCAMLONG=''
  GPHOTOCAM1=''
  GPHOTOCAM2=''
}

function have_cams {
  if test -z "$LEFTCAM" -o -z "$RIGHTCAM" ; then
    return 1
  fi
  return 0
}

function detect_cams {
  forget_cams
  CAMS=$("$GPHOTO2" --auto-detect|grep usb| wc -l)
  if test $CAMS -eq 2 ; then
    GPHOTOCAM1=$("$GPHOTO2" --auto-detect|grep usb|sed -e 's/.*Camera *//g'|head -n1)
    GPHOTOCAM2=$("$GPHOTO2" --auto-detect|grep usb|sed -e 's/.*Camera *//g'|tail -n1)
    echo $GPHOTOCAM1" is gphotocam1"
    echo $GPHOTOCAM2" is gphotocam2"
    
    GPHOTOCAM1ORIENTATION=$("$GPHOTO2" --port $GPHOTOCAM1 --get-config /main/settings/ownername|grep Current|sed -e's/.*\ //')
    GPHOTOCAM2ORIENTATION=$("$GPHOTO2" --port $GPHOTOCAM2 --get-config /main/settings/ownername|grep Current|sed -e's/.*\ //')

    echo $GPHOTOCAM1ORIENTATION" is gphotocam1orientation"
    echo $GPHOTOCAM2ORIENTATION" is gphotocam2orientation"

    CAM1=$(echo $GPHOTOCAM1|sed -e 's/.*,//g')
    CAM2=$(echo $GPHOTOCAM2|sed -e 's/.*,//g')
    echo "Detected 2 camera devices: $GPHOTOCAM1 and $GPHOTOCAM2"
  else
    echo "Number of camera devices does not equal 2. Giving up." 1>&2
    forget_cams
    return 1
  fi
  if test "$GPHOTOCAM1ORIENTATION" == "left" ; then
    LEFTCAM=$(echo $GPHOTOCAM1|sed -e 's/.*,//g')
    LEFTCAMLONG=$GPHOTOCAM1
  elif test "$GPHOTOCAM1ORIENTATION" == "right" ; then
    RIGHTCAM=$(echo $GPHOTOCAM1| sed -e 's/.*,//g')
    RIGHTCAMLONG=$GPHOTOCAM1
  else
    echo "$GPHOTOCAM1 owner name is neither set to left or right. Please configure that before continuing." 1>&2
    forget_cams
    return 1
  fi
  if test "$GPHOTOCAM2ORIENTATION" == "left" ; then
    LEFTCAM=$(echo $GPHOTOCAM2|sed -e 's/.*,//g')
    LEFTCAMLONG=$GPHOTOCAM2
  elif test "$GPHOTOCAM2ORIENTATION" == "right" ; then
    RIGHTCAM=$(echo $GPHOTOCAM2| sed -e 's/.*,//g')
    RIGHTCAMLONG=$GPHOTOCAM2
  else
    echo "$GPHOTOCAM2 owner name is neither set to left or right. Please configure that before continuing." 1>&2
    forget_cams
    return 1
  fi
  return 0
}

function ptp_chdk_exec_cam_int {
  local dev
  local cmd
  local first
  if test $# -lt 2 -o -z "$1" -o -z "$2" ; then
    echo "ptp_chdk_exec_cam_int: usage ptp_chdk_exec_cam_int <dev> <chdk-command>" 1>&2
    return 1
  fi
  dev="$1"
  shift
  first=YES
  for cmd in "$@" ; do
    if test "$first" = "YES" ; then
      first=NO
    else
      camera_delay_short
    fi
    "$PTPCAM" --dev="$dev" --chdk="$cmd"
    if test $? -ne 0 ; then
      echo "ptp command '$cmd' fails for $dev" 1>&2
      return 1
    fi
  done
  return 0
}

function ptp_chdk_exec_left_cam {
  local cmd
  if test -z "$LEFTCAM" ; then
    echo "ptp_chdk_exec_right_cam: No right camera known" 1>&2
    return 1
  fi
  ptp_chdk_exec_cam_int "$LEFTCAM" "$@"
  return $?
}

function ptp_chdk_exec_right_cam {
  local cmd
  if test -z "$RIGHTCAM" ; then
    echo "ptp_chdk_exec_right_cam: No right camera known" 1>&2
    return 1
  fi
  ptp_chdk_exec_cam_int "$RIGHTCAM" "$@"
  return $?
}

function ptp_chdk_exec_cams {
  local rl
  local rr
  ptp_chdk_exec_left_cam "$@"
  rl=$?
  if test $rl -eq 0 ; then
    camera_delay_short
    ptp_chdk_exec_right_cam "$@"
    rr=$?
  else
    rr=1
  fi
  if test $rl -ne 0 -o $rr -ne 0 ; then
    return 1
  fi
  return 0
}

function init_cams_full {
  echo "Detecting cameras"
  detect_cams
  if test $? -ne 0 ; then
    echo "Can't detect cams. Abort." 1>&2
    return 1
  fi
  camera_delay_short

  echo "Setting cameras to shooting mode"
  ptp_chdk_exec_cams 'mode 1'
  if test $? -ne 0 ; then
    echo "Can't set recording mode. Abort." 1>&2
    return 1
  fi
  camera_delay_short

  echo "Disabling flash"
  ptp_chdk_exec_cams 'lua while(get_flash_mode()<2) do click("right") end'
  if test $? -ne 0 ; then
    echo "Can't disable flash. Abort." 1>&2
    return 1
  fi
  camera_delay_short

  if test -n "$ZOOMLVL" ; then
    echo "Set zoom level"
    ptp_chdk_exec_cams 'lua set_zoom('"$ZOOMLVL"')'
    if test $? -ne 0 ; then
      echo "Can't set zoom. Abort." 1>&2
      return 1
    fi
  fi
  camera_delay_short

  echo "Performing autofocus"
  ptp_chdk_exec_cams 'lua set_aflock(0); sleep(200); while (get_focus()==nil) do press("shoot_half"); sleep(800); release("shoot_half"); sleep(800); end set_aflock(1); sleep(200)'
  if test $? -ne 0 ; then
    echo "Can't lock to autofocus. Abort." 1>&2
    return 1
  fi
  camera_delay_short

  echo "Checking zoom (should be 18)"
  ptp_chdk_exec_cams 'luar get_zoom()'
  camera_delay_short

  echo "Checking focus (should be around 430-470)"
  ptp_chdk_exec_cams 'luar get_focus()'
  camera_delay_short

  echo "Setting ISO"
  ptp_chdk_exec_cams 'lua set_iso_real(50)'
  if test $? -ne 0 ; then
    echo "Can't set ISO. Abort." 1>&2
    return 1
  fi
  camera_delay_short

  echo "Disabling neutrality density filter"
  ptp_chdk_exec_cams 'lua set_nd_filter(2)'
  if test $? -ne 0 ; then
    echo "Can't disable nd. Abort." 1>&2
    return 1
  fi
  camera_delay_short

  return 0
}

function shoot_left_cam {
  ptp_chdk_exec_left_cam 'lua set_iso_real(50); set_tv96(320); sleep(100); shoot()'
  if test $? -ne 0 ; then
    echo "Can't shoot. Abort."
    return 1
  fi
  return 0
}

function shoot_right_cam {
  ptp_chdk_exec_right_cam 'lua set_iso_real(50); set_tv96(320); sleep(100); shoot()'
  if test $? -ne 0 ; then
    echo "Can't shoot. Abort."
    return 1
  fi
  return 0
}

function jpeg_rotate_inplace {
  local tmp
  if test $# -ne 2 -o '(' "$1" != '90' -a "$1" != '180' -a "$1" != '270' ')' -o -z "$2" -o '!' -r "$2" ; then
    echo "jpeg_rotate_inplace: usage jpeg_rotate_inplace < 90|180|270> <file>"
    return 1
  fi
  tmp="$2"'.t'
  jpegtran -rotate "$1" "$2" > "$tmp"
  if test $? -ne 0 -o '!' -s "$tmp" ; then
    return 1
  fi
  mv -f "$tmp" "$2"
  if test $? -ne 0 -o -e "$tmp" ; then
    return 1
  fi
  return 0  
}

function archive_page_photos {
  local sd
  sd="$(pwd)""/""$(date '+%Y%m%dT%H%M%S')"
  mkdir "$sd"
  if test $? -ne 0 ; then
    return 1
  fi
  mv "$(pwd)""/"pg-*.jpg "$sd""/"
  if test $? -ne 0 ; then
    return 0
  fi
  mk_dummy_last_files
  return 0
}

function download_last_int {
  local dev
  local rp
  local lp
  if test $# -ne 1 -o -z "$1" ; then
    echo "download_last_int: usage download_last_int <dev>"
    return 1
  fi
  dev="$1"

  rp="$(ptp_chdk_exec_cam_int "$dev" 'luar string.format('\''%s/IMG_%04d.JPG'\'',get_image_dir(),get_exp_count())' | sed -n 's,^[0-9][0-9]*:ret:'\''\([A-Za-z0-9_-][A-Za-z0-9_/.-]*[A-Za-z0-9_-]\)'\''.*$,\1,p')"
  if test -z "$rp" ; then
    echo "Can't get photo remote path."
    return 1
  fi

  lp="$(local_file_name)"
  ptp_chdk_exec_cam_int "$dev" "download $rp $lp"
  echo "$lp"
}

function download_last_left_cam {
  if test -z "$LEFTCAM" ; then
    echo "ptp_chdk_exec_right_cam: No right camera known"
    return 1
  fi
  download_last_int "$LEFTCAM"
}

function download_last_right_cam {
  if test -z "$RIGHTCAM" ; then
    echo "ptp_chdk_exec_right_cam: No right camera known"
    return 1
  fi
  download_last_int "$RIGHTCAM"
}

function read_key {
  local k1
  local k2
  read -s -N1 k1
  if ! echo "$k1" | grep '^[a-zA-Z0-9]$' >/dev/null 2>&1; then
    return 1
  fi
  if test $# -gt 0 -a "$1" = "-d" ; then
    read -s -N1 -t 0.8 k2
    if test -n "$k2" ; then
      if echo "$k2" | grep '^[a-zA-Z0-9]$' >/dev/null 2>&1; then
        echo "$k1$k2"
        return 0
      else
        return 1
      fi
    fi
  fi
  echo "$k1"
  return 0
}

function mk_dummy_last_files {
  local red="255 0 0"
  local green="0 255 0"
  local blue="0 0 255"
  local yellow="255 255 0"

  rm -f last_left.jpg
  rm -f last_right.jpg
  (echo 'P3'; echo '2 2 255'; echo "$red $green $green $red") | pnmscale -xsize 48 -ysize 64 | cjpeg > last_left.jpg
  (echo 'P3'; echo '2 2 255'; echo "$blue $yellow $yellow $blue") | pnmscale -xsize 48 -ysize 64 | cjpeg > last_right.jpg
  if ! test -s last_left.jpg -a -s last_right.jpg ; then
    echo "Can't create dummy files." 1>&2
    return 1
  fi
  return 0
}

function delete_all_from_cams {
  if ! have_cams ; then
    return 1
  fi
  "$GPHOTO2" --port $GPHOTOCAM1 --recurse -D A/store00010001/DCIM/; true
  camera_delay_short
  "$GPHOTO2" --port $GPHOTOCAM2 --recurse -D A/store00010001/DCIM/; true
  return 0
}

function shoot_pages {
  local pc_save
  pc_save=$PHOTOCOUNTER

  shoot_left_cam
  if test $? -ne 0 ; then
    echo "Shooting left camera failed. Abort."
    PHOTOCOUNTER=$pc_save
    return 1
  fi
  camera_delay_full
  
  shoot_right_cam
  if test $? -ne 0 ; then
    echo "Shooting right camera failed. Abort."
    PHOTOCOUNTER=$pc_save
    return 1
  fi
  camera_delay_full
  
  PHOTOCOUNTER=$(expr $PHOTOCOUNTER + 1)
  left_photo="$(download_last_left_cam)"
  if test $? -ne 0 -o -z "$left_photo" ; then
    echo "Download from left camera failed. Abort."
    PHOTOCOUNTER=$pc_save
    return 1
  fi
  echo "Downloaded $left_photo from left camera."

  ( ( jpeg_rotate_inplace 270 "$left_photo" && && ln -f "$left_photo" last_left.jpg ) || ( echo "ERROR" ; echo "ERROR" ; echo "ERROR" ; echo "Error in rotating left page." ; echo "ERROR" ; echo "ERROR" ; echo "ERROR" ) ) &
  camera_delay_short
  
  PHOTOCOUNTER=$(expr $PHOTOCOUNTER + 1)
  right_photo="$(download_last_right_cam)"
  if test $? -ne 0 -o -z "$right_photo" ; then
    echo "Download from right camera failed. Abort."
    PHOTOCOUNTER=$pc_save
    return 1
  fi
  echo "Downloaded $right_photo from right camera."
  ( ( jpeg_rotate_inplace 90 "$right_photo" && && ln -f "$right_photo" last_right.jpg ) || ( echo "ERROR" ; echo "ERROR" ; echo "ERROR" ; echo "Error in rotating right page." ; echo "ERROR" ; echo "ERROR" ; echo "ERROR" ) ) &
  camera_delay_short

  return 0
}

mk_dummy_last_files
if test $? -ne 0 ; then
  echo "Can't create dummy placeholders for last shots." 1>&2
  exit 1
fi

init_cams_full
if test $? -ne 0 ; then
  echo "Unable to initialize cameras for shooting"
  exit 1
fi
echo "Cameras initialized. We are ready to roll."

while : ; do
  echo ""
  echo ""
  echo "We are ready for next shoot"
  echo "Press pedal to shoot the next pages (""$(expr $PHOTOCOUNTER + 1)""-""$(expr $PHOTOCOUNTER + 2)"")."
  if test $PHOTOCOUNTER -ge 2 ; then
    echo "Double press pedal or press r to shoot the last pages again (""$(expr $PHOTOCOUNTER - 1)""-""$PHOTOCOUNTER"")."
  fi
  echo "Press q to quit."
  echo "Press c to reinitialize camera."
  echo "Press a to archive current book and reset page counter."
  press="$(read_key -d)"
  if test '(' "$press" = "bb" -o "$press" = "r" -o "$press" = "rr" ')' ; then
    if test $PHOTOCOUNTER -ge 2 ; then
      echo "Rewinding the page counter by 2."
      PHOTOCOUNTER=$(expr $PHOTOCOUNTER - 2)
      press="b"
    else
      echo "No previous shoot."
      continue
    fi
  fi
  if test "$press" = "q" -o "$press" = "qq" ; then
    rm -f last_left.jpg last_right.jpg
    echo "Cleaning up."
    if have_cams ; then
      ptp_chdk_exec_cams 'lua set_aflock(0)'
      camera_delay_short
      delete_all_from_cams
    fi
    echo "All done. Good bye."
    exit
  elif test "$press" = "b" ; then
    echo "Shooting cameras."
    if ! have_cams ; then
      echo "Cameras are not initialized. Try to reinitialize them."
      continue
    fi
    shoot_pages
    if test $? -ne 0; then
      echo "Pages were not shot successfully and page counters are not updated."
      echo "You probably want to reinitialize cameras and shoot again."
      forget_cams
    fi
  elif test "$press" = "c" -o "$press" = "cc" ; then
    init_cams_full
    if test $? -ne 0 ; then
      echo "Can't reinitialize cameras. Give them hard reset and try again."
    else
      echo "Camera initialization is ok."
      echo "You probably ended here because your camera crashed, so most probably you should now reshoot the last pages."
    fi
  elif test "$press" = "a" -o "$press" = "aa" ; then
    echo "Archiving current photos."
    archive_page_photos
    if test $? -eq 0 ; then
      echo "Archived.  Photo page counter reset done."
      PHOTOCOUNTER=0
    else
      echo "Archiving failed. Photos remain in the current dir."
      echo "Photo counter is NOT reset."
    fi
  else
    echo "Unknown key."
  fi
done
