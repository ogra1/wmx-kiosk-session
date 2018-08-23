#!/bin/bash
set -e

# Ensure XWAYLAND_FULLSCREEN_WINDOW_HINT is set
if [ -z ${XWAYLAND_FULLSCREEN_WINDOW_HINT+x} ]; then
  echo "The XWAYLAND_FULLSCREEN_WINDOW_HINT was not specified in the snapcraft.yaml file"
  exit 1
fi

# Xwayland needs to run as root (bug lp:1767372), so everything has to
if [ "$EUID" -ne 0 ]; then
  echo "This needs to run as root"
  exit 2
fi

if [ -z ${WAYLAND_SOCKET_DIR+x} ]; then
  echo "The WAYLAND_SOCKET_DIR was not specified in the snapcraft.yaml file, using fallback."
  WAYLAND_SOCKET_DIR=$XDG_RUNTIME_DIR
else
  # Ensure wayland-socket-dir connection established
  if [ ! -d $WAYLAND_SOCKET_DIR ]; then
    echo "##################################################################################"
    echo "You need to connect this snap to one which implements the wayland-socket-dir plug."
    echo ""
    echo "You can do this with these commands:"
    echo "  snap install mir-kiosk --beta"
    echo "  snap connect $SNAP_NAME:wayland-socket-dir mir-kiosk:wayland-socket-dir"
    echo "##################################################################################"
    exit 3
  fi
fi

# If necessary, set up minimal environment for Xwayland to function
if [ -z ${LIBGL_DRIVERS_PATH+x} ]; then
  if [ "$SNAP_ARCH" == "amd64" ]; then
    ARCH="x86_64-linux-gnu"
  elif [ "$SNAP_ARCH" == "armhf" ]; then
    ARCH="arm-linux-gnueabihf"
  elif [ "$SNAP_ARCH" == "arm64" ]; then
    ARCH="aarch64-linux-gnu"
  else
    ARCH="$SNAP_ARCH-linux-gnu"
  fi

  export LIBGL_DRIVERS_PATH=$SNAP/usr/lib/$ARCH/dri
fi

# Use new port number in case old server clean up wasn't successful
let port=$RANDOM%100
# Avoid low numbers as they may be used by desktop
let port+=4

# We need a simple window manager to make the client application fullscreen.
# Am using i3 here, so generate a simple config file for it.
I3_CONFIG=$SNAP_DATA/i3.config

cat <<EOF >> "$I3_CONFIG"
# i3 config file (v4)
font pango:monospace 8
# set window for fullscreen
for_window [${XWAYLAND_FULLSCREEN_WINDOW_HINT}] fullscreen
EOF

# Launch Xwayland.
# Wayland clients look for the wayland socket in $XDG_RUNTIME_DIR, so need to override
# that explicitly to where we specified in the YAML file.
XDG_RUNTIME_DIR=$WAYLAND_SOCKET_DIR \
SNAPPY_PRELOAD=$SNAP \
LD_PRELOAD=$SNAP/lib/libxwayland-preload.so \
  $SNAP/usr/bin/Xwayland -terminate :${port} \
  -fp $SNAP/usr/share/fonts/truetype/dejavu,$SNAP/usr/share/fonts/X11/misc,$SNAP/usr/share/fonts/X11/Type1,$SNAP/usr/share/fonts/X11/100dpi,$SNAP/usr/share/fonts/X11/75dpi & pid=$!

trap "trap - SIGTERM && kill $pid" SIGINT SIGTERM EXIT # kill on signal or quit
sleep 1 # FIXME - Xwayland does emit SIGUSR1 when ready for client connections

export DISPLAY=:${port}

export XDG_DATA_HOME=$SNAP/usr/share
export FONTCONFIG_PATH=$SNAP/etc/fonts/conf.d
export FONTCONFIG_FILE=$SNAP/etc/fonts/fonts.conf

# Avoid using $XDG_RUNTIME_DIR until LP: #1656340 is fixed
XDG_RUNTIME_DIR=$SNAP_DATA \
  $SNAP/bin/wmx && exit 1
