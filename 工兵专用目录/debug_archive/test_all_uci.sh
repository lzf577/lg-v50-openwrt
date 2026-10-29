#!/bin/sh
for cfg in $(ls /etc/config); do
  res=$(ubus call uci get "{\"config\":\"$cfg\"}" 2>&1)
  if [ $? -ne 0 ]; then
    echo "FAILED: $cfg -> $res"
  fi
done
