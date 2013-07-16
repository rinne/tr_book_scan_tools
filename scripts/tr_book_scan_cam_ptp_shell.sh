#! /bin/bash

export LANG=C
PTPCAM='/opt/diybookscanner/bin/ptpcam'
GPHOTO2='/usr/bin/gphoto2'
DETECT_CAMS='/opt/diybookscanner/bin/tr_book_scan_cam_detect.sh'
TIMEOUT3='/opt/diybookscanner/bin/timeout3'

eval "$("$DETECT_CAMS")"

cam=""
ori=""
if test $# -eq 1 -a "$1" = "left" ; then
  if test -n "$CAM_PTP_LEFT" ; then
    cam="$CAM_PTP_LEFT"
    ori=left
  fi
elif test $# -eq 1 -a "$1" = "right" ; then
  if test -n "$CAM_PTP_RIGHT" ; then
    cam="$CAM_PTP_RIGHT"
    ori=right
  fi
elif test $# -eq 0 ; then
  if test -n "$CAM_PTP_LEFT" ; then
    cam="$CAM_PTP_LEFT"
    ori=left
  elif test -z "$CAM_PTP_RIGHT" ; then
    cam="$CAM_PTP_RIGHT"
    ori=right
  fi
else
  echo "usage: $0 [ left | right ]" 1>&2
  exit 1
fi

if test -z "$cam" ; then
  echo "Camera not found." 1>&2
  exit 1
fi

echo "Using $ori camera $cam"
"$PTPCAM" --dev="$cam" --chdk
