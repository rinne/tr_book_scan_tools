#! /bin/bash

export LANG=C
PTPCAM='/opt/diybookscanner/bin/ptpcam'
GPHOTO2='/usr/bin/gphoto2'

function detect_cams {
  local i
  local is
  local own
  local cnt=0
  local lc=""
  local rc=""
  local lcs=""
  local rcs=""
  local all=""
  for i in $("$GPHOTO2" --auto-detect | sed -n 's/^.* \(usb:[0-9][0-9][0-9],[0-9][0-9][0-9]\)/\1/p') ; do
    is="$(echo "$i" | sed -n 's/^usb:[0-9][0-9][0-9],\([0-9][0-9][0-9]\)$/\1/p')"
    if test -z "$is" ; then
      echo "# Can't create a short form camera id. Giving up."
      return 1
    fi
    ori="$("$GPHOTO2" --port "$i" --get-config /main/settings/ownername 2>/dev/null | sed -n 's,^Current: \(.*\)$,\1,p' | head -1)"
    if test $ori = "left" ; then
      if test -z "$lc" ; then
        lc="$i"
        lcs="$is"
      else
        echo "# Found two left page cameras. Giving up."
        return 1
      fi
    elif test $ori = "right" ; then
      if test -z "$rc" ; then
        rc="$i"
        rcs="$is"
      else
        echo "# Found two right page cameras. Giving up."
        return 1
      fi
    fi
    cnt=$(expr $cnt + 1)
    if test -z "$all" ; then
      all="$i"
    else
      all="$all $i"
    fi
  done

  if test $cnt -gt 0 ; then
    echo "# Detected $cnt cameras."
    echo "# USB identifiers: $all"
  else
    echo "# No cameras detected."
  fi
  if test -n "$lc" ; then
    echo "# Left camera"
    echo "export CAM_PTP_LEFT=""$lcs"
    echo "export CAM_GPHOTO2_LEFT=""$lc"
  else
    echo "# Left camera not detected"
    echo "export CAM_PTP_LEFT=''"
    echo "export CAM_GPHOTO2_LEFT=''"
  fi
  if test -n "$rc" ; then
    echo "# Right camera"
    echo "export CAM_PTP_LEFT=""$rcs"
    echo "export CAM_GPHOTO2_LEFT=""$rc"
  else
    echo "# Right camera not detected"
    echo "export CAM_PTP_LEFT=''"
    echo "export CAM_GPHOTO2_LEFT=''"
  fi
  return 0
}

detect_cams

exit $?
