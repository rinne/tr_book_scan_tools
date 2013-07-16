#! /bin/bash

export LANG=C
PTPCAM='/opt/diybookscanner/bin/ptpcam'
GPHOTO2='/usr/bin/gphoto2'
DETECT_CAMS='/opt/diybookscanner/bin/tr_book_scan_cam_detect.sh'
TIMEOUT3='/opt/diybookscanner/bin/timeout3'

ZOOMLVL=18

rvf_l="/tmp/tr_rv_left.$$"
rvf_r="/tmp/tr_rv_right.$$"
rvf_g="/tmp/tr_rv_gen.$$"

function cam_forget() {
  CAM_PTP_RIGHT=''
  CAM_PTP_LEFT=''
  CAM_GPHOTO2_RIGHT=''
  CAM_GPHOTO2_LEFT=''
}

cam_forget

function cam_initialized() {
  if test -n "$CAM_PTP_RIGHT" -a "$CAM_PTP_LEFT" ; then
    return 0
  fi
  return 1
}

function cam_chdk() {
  if test $# -ne 2 ; then
    echo "Usage: $0 cam script"
    return 1
  fi
  local dev="$1"
  local script="$2"
  local rv="$("$TIMEOUT3" -t 10 "$PTPCAM" --dev="$dev" --chdk="$script" | sed -n 's,^script:\([0-9][0-9]*\)$,\1,p' | head -1)"
  test -n "$rv"
  return $?
}

function cam_luar() {
  if test $# -ne 3 ; then
    echo "Usage: $0 cam resultfile script"
    return 1
  fi
  local dev="$1"
  local resultfile="$2"
  local resulttypefile="$resultfile"'.type'
  local script="$3"
  rm -f "$resultfile" "$resulttypefile"
  local chdk='luar loadstring("'"$script"'")()'
  local rt=''
  local rv="$("$TIMEOUT3" -t 10 "$PTPCAM" --dev="$dev" --chdk="$chdk" | sed -n 's,^[0-9][0-9]*:ret:\(.*\)$,\1,p' | head -1)"
  if test -z "$rv" ; then
    return 1
  fi
  if test -z "$rv" ; then
    return 1
  elif test "$rv" = "nil" ; then
    rt="nil"
    rv=""
  elif echo "$rv" | grep '^[0-9][0-9]* ([0-9a-f][0-9a-f]*)$' >/dev/null ; then
    rt="int"
    rv="$(echo "$rv" | sed 's,^\([0-9][0-9]*\) ([0-9a-f][0-9a-f]*)$,\1,')"
  elif echo "$rv" | grep '^'.*'$' >/dev/null ; then
    rt="string"
    rv="$(echo "$rv" | sed 's,^.\(.*\).$,\1,')"
  elif echo "$rv" | grep '^[0-9][0-9]*$' >/dev/null ; then
    rt="int"
    true
  else
    return 1
  fi
  echo -n "$rv" > "$resultfile" && echo -n "$rt" > "$resulttypefile"
  return $?
}

function cam_download() {
  if test $# -ne 3 ; then
    echo "Usage: $0 cam remotefile localfile"
    return 1
  fi
  local dev="$1"
  local remotefile="$2"
  local localfile="$3"
  rm -f "$localfile"
  "$TIMEOUT3" -t 10 "$PTPCAM" --dev="$dev" --chdk="download $remotefile $localfile"
}

function cam_shoot() {
  if test $# -ne 2 -o -z "$1" -o -z "$2" -o "$1" = "$2" ; then
    echo "Usage: $0 left-destination-file right-destination-file"
    return 1
  fi
  local lf="$1"
  local rf="$2"

  rm -rf "$lf" "$rf"

  local shoot="set_iso_real(50); set_nd_filter(2); set_tv96(320); ec0=get_exp_count(); shoot(); ec1=get_exp_count(); id=get_image_dir(); if (ec1==ec0) then return nil else return string.format('%s/IMG_%04d.JPG',id,ec1) end"

  cam_luar "$CAM_PTP_LEFT" "$rvf_l" "$shoot" &
  lp=$!
  sleep 0.1
  cam_luar "$CAM_PTP_RIGHT" "$rvf_r" "$shoot" &
  rp=$!

  wait $lp
  if test $? -ne 0 ; then
    echo "Shooting left camera fails"
    return 1
  fi

  wait $rp
  if test $? -ne 0 ; then
    echo "Shooting right camera fails"
    return 1
  fi

  local rlt="$(cat "$rvf_l"'.type')"
  if test "$rlt" != "string" ; then
    echo "Left camera returns unexpected type for filename."
    return 1
  fi
  local rlf="$(cat "$rvf_l")"

  local rrt="$(cat "$rvf_r"'.type')"
  if test "$rrt" != "string" ; then
    echo "Right camera returns unexpected type for filename."
    return 1
  fi
  local rrf="$(cat "$rvf_r")"

  cam_download "$CAM_PTP_LEFT" "$rlf" "$lf" &
  lp=$!
  sleep 0.1
  cam_download "$CAM_PTP_RIGHT" "$rrf" "$rf" &
  rp=$!

  wait $lp
  if test $? -ne 0 -o '!' -f "$lf" -a -s  "$lf" ; then
    echo "Download from left camera fails"
    return 1
  fi

  wait $rp
  if test $? -ne 0 -o '!' -f "$rf" -a -s  "$rf" ; then
    echo "Download from right camera fails"
  fi

  return 0
}

function cam_set_zoom() {
  if test $# -ne 2 ; then
    echo "Usage: $0 cam"
    return 1
  fi
  local dev="$1"
  local zoom="$2"
  local rv
  local rt
  echo "Setting zoom level"
  cam_luar "$dev" "$rvf_g" "set_iso_real(50); set_zoom('"$zoom"'); sleep(100); return get_zoom()";
  if test $? -ne 0 ; then
    return 1
  fi
  rv="$(cat "$rvf_g")"
  rt="$(cat "$rvf_g"'.type')"
  if test "$rt" != "int" ; then
    echo "Error setting zoom. Unexpected return type $rt when expecting int."
    return 1
  fi
  if test "$rv" -ne "$zoom" ; then
    echo "Error setting zoom. Expecting $zoom, got $rv."
    return 1
  fi

}

function cam_setup() {
  if test $# -ne 1 ; then
    echo "Usage: $0 cam"
    return 1
  fi
  local dev="$1"
  local rv
  local rt

  echo "Setting camera mode"
  cam_chdk "$dev" "mode 1"
  if test $? -ne 0 ; then
    return 1
  fi

  echo "Disabling flash"
  cam_luar "$dev" "$rvf_g" "while (get_flash_mode()<2) do click("right") end sleep(100); return get_flash_mode()"
  if test $? -ne 0 ; then
    return 1
  fi
  rv="$(cat "$rvf_g")"
  rt="$(cat "$rvf_g"'.type')"
  if test "$rt" != "int" ; then
    echo "Error setting flash mode. Unexpected return type $rt when expecting int."
    return 1
  fi
  if test "$rv" -ne 2 ; then
    echo "Error setting flash mode. Expecting 2, got $rv."
    return 1
  fi
 
  cam_set_zoom "$dev" "$ZOOMLVL"
  if test $? -ne 0 ; then
    echo "Error setting zoom."
    return 1
  fi

  echo "Setting autofocus"
  cam_chdk "$dev" "lua set_aflock(0)"
  sleep 0.1
  cam_luar "$dev" "$rvf_g" "press('shoot_half'); sleep(800); release('shoot_half'); set_aflock(1); sleep(800); return get_focus()"
  if test $? -ne 0 ; then
    echo "Autofocus setting fails."
    return 1
  fi
  rv="$(cat "$rvf_g")"
  rt="$(cat "$rvf_g"'.type')"
  if test "$rt" != "int" ; then
    echo "Error setting autofocus. Unexpected return type $rt when expecting int."
    return 1
  fi
  echo "Autofocus setting returns value $rv"
  cam_luar "$dev" "$rvf_g" "return get_focus()"
  if test $? -ne 0 ; then
    echo "Autofocus value retrieval fails."
    return 1
  fi
  rv="$(cat "$rvf_g")"
  rt="$(cat "$rvf_g"'.type')"
  if test "$rt" != "int" ; then
    echo "Error confirming autofocus value. Unexpected return type $rt when expecting int."
    return 1
  fi
  echo "Autofocus check returns value $rv"
  if test "$rv" -lt 430 -o "$rv" -ge 480 ; then
    echo "Nominal autofocus is around 440-455 with this setup."
    echo "You might like to reinitialize the camera."
  fi
  return 0
}

function cam_setup_both() {
  echo "Setting up left camera $CAM_PTP_LEFT"
  cam_setup "$CAM_PTP_LEFT"
  if test $? -ne 0 ; then
    echo "Left camera setup fails."
    return 1
  fi
  sleep 1
  echo "Setting up right camera $CAM_PTP_RIGHT"
  cam_setup "$CAM_PTP_RIGHT"
  if test $? -ne 0 ; then
    echo "Right camera setup fails."
    return 1
  fi
  return 0
}

function read_key() {
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

function local_page_file_name() {
  printf "%s/pg-%04d.jpg" "$(pwd)" $1
}

function local_cover_file_name() {
  printf "%s/cover-%04d.jpg" "$(pwd)" $1
}

function archive_photos() {
  local x
  sd="$(pwd)"'/'"$(date '+%Y%m%dT%H%M%S')"'/'
  mkdir "$sd"
  if test $? -ne 0 ; then
    return 1
  fi
  x=1
  while test $x -le $1 ; do
    mv "$(local_page_file_name $x)" "$sd"
    if test $? -ne 0 ; then
      return 1
    fi
    x=$(expr $x + 1)
  done
  x=1
  while test $x -le $2 ; do
    mv "$(local_cover_file_name $x)" "$sd"
    if test $? -ne 0 ; then
      return 1
    fi
    x=$(expr $x + 1)
  done
  return 0  
}

cover_no=0
page_no=0

while true ; do
  page_no_plus1=$(expr $page_no + 1)
  page_no_plus2=$(expr $page_no + 2)

  cover_no_plus1=$(expr $cover_no + 1)
  cover_no_plus2=$(expr $cover_no + 2)

  if cam_initialized ; then
    cam_initialized=YES
  else
    cam_initialized=NO
  fi

  echo ""
  if test $cam_initialized = YES ; then
    echo "Press pedal or b to photograph pages $page_no_plus1 and $page_no_plus2"
    echo "Press c to photograph cover pages $cover_no_plus1 and $cover_no_plus2"
  else
    echo "Cameras are not initialized. Photo shooting is currently not possible."
  fi
  if test $page_no -gt 1 ; then
    echo "Double press pedal or press r to return to last shot pages"
  fi
  echo "Press i to (re)initialize cameras"
  if test $page_no -gt 0 -o $cover_no -gt 0 ; then
    echo "Press a to archive current shots and reset page counters and start a new book"
  fi
  echo "Press q to quit"
  echo ""

  k="$(read_key -d)"

  if test "$k" = "q" -o "$k" = "qq" ; then
    echo "Quit"
    if test $page_no -gt 0 -o $cover_no -gt 0 ; then
      archive_photos $page_no $cover_no
      if test $? -eq 0 ; then
        cover_no=0
        page_no=0
      else
        echo "Photo archiving failed."
        echo "Solve the issue in scan dir manually."
      fi
    fi
    exit
  elif test '(' $page_no -gt 0 -o $cover_no -gt 0 ')' -a '(' "$k" = "a" -o "$k" = "aa" ')' ; then
    echo "Archive"
    archive_photos $page_no $cover_no
    if test $? -eq 0 ; then
      cover_no=0
      page_no=0
    else
      echo "Photo archiving failed."
      echo "Solve the issue in scan dir manually."
      echo "Abort."
      exit
    fi
  elif test  $page_no -gt 1 -a "$k" = "bb" -o "$k" = "r" -o "$k" = "r" ; then
    echo "Rewind"
    rm -f "$(local_page_file_name $page_no)"
    page_no=$(expr $page_no - 1)
    rm -f "$(local_page_file_name $page_no)"
    page_no=$(expr $page_no - 1)
  elif test $cam_initialized = YES -a "$k" = "c" ; then
    echo "Shoot cover page."
    left_file="$(local_cover_file_name $cover_no_plus1)"
    right_file="$(local_cover_file_name $cover_no_plus2)"
    cam_shoot "$left_file" "$right_file"
    if test $? -eq 0 ; then
      if test -e last_left.jpg ; then
        mv -f last_left.jpg prev_left.jpg
      fi
      ln -f "$left_file" last_left.jpg
      if test -e last_right.jpg ; then
        mv -f last_right.jpg prev_right.jpg
      fi
      ln -f "$right_file" last_right.jpg
      cover_no=$(expr $cover_no + 2)
    else
      echo "-*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*-"
      echo "-*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*-"
      echo ""
      echo "Photo shot failed. You probably have to reinitialize cameras."
      echo "Notice that page counter was not updated, so after reinitialization"
      echo "you can continue by shooting the page again without rewind."
      echo ""
      echo "-*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*-"
      echo "-*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*-"
      cam_forget
    fi
  elif test $cam_initialized = YES -a "$k" = "b" ; then
    echo "Shoot normal page."
    left_file="$(local_page_file_name $page_no_plus1)"
    right_file="$(local_page_file_name $page_no_plus2)"
    cam_shoot "$left_file" "$right_file"
    if test $? -eq 0 ; then
      if test -e last_left.jpg ; then
        mv -f last_left.jpg prev_left.jpg
      fi
      ln -f "$left_file" last_left.jpg
      if test -e last_right.jpg ; then
        mv -f last_right.jpg prev_right.jpg
      fi
      ln -f "$right_file" last_right.jpg
      page_no=$(expr $page_no + 2)
    else
      echo "-*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*-"
      echo "-*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*-"
      echo ""
      echo "Photo shot failed. You probably have to reinitialize cameras."
      echo "Notice that page counter was not updated, so after reinitialization"
      echo "you can continue by shooting the page again without rewind."
      echo ""
      echo "-*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*-"
      echo "-*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*- ERROR -*-"
      cam_forget
    fi
  elif test "$k" = "i" -o "$k" = "ii" ; then
    echo "Reinitialize cameras."
    cam_forget
    eval "$("$DETECT_CAMS")"
    if test -z "$CAM_PTP_RIGHT" -a -z "$CAM_PTP_LEFT" ; then
      echo "Both cameras are missing."
    elif test -z "$CAM_PTP_RIGHT" ; then
      echo "Right camera is missing."
    elif test -z "$CAM_PTP_LEFT" ; then
      echo "Left camera is missing."
    else
      cam_setup_both
      if test $? -ne 0 ; then
        echo "Camera setup fails."
        cam_forget
      fi
    fi
  else
    echo "Invalid key."
  fi

done
