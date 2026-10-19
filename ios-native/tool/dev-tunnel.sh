#!/bin/sh
# Run in its own terminal. Ctrl-C closes only this development tunnel.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec ssh -N -o BatchMode=yes -o StrictHostKeyChecking=yes \
  -o "UserKnownHostsFile=$script_dir/vm20000_known_hosts" \
  -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
  -L 127.0.0.1:19820:127.0.0.1:8080 widowsbuild@10.44.0.200
