#!/bin/bash

# Variables
user_name="autom4b"
user_id="1000"
group_id="1000"

# Check if PUID and PGID are set, otherwise use default
if [ -n "${PUID}" ]; then
  user_id="${PUID}"
fi

if [ -n "${PGID}" ]; then
  group_id="${PGID}"
fi

# Create the group if it does not exist
if ! getent group "${user_name}" > /dev/null 2>&1; then
  addgroup --gid "${group_id}" "${user_name}"
fi

# Create the user if it does not exist
if ! id -u "${user_name}" > /dev/null 2>&1; then
  adduser --uid "${user_id}" --gid "${group_id}" --disabled-password --gecos "" "${user_name}"
  echo "Created missing ${user_name} user with UID ${user_id} and GID ${group_id}"
fi

# Optional: Change directory if needed
# cd /temp/mp3merge

# Copy the script if needed
# file="/temp/mp3merge/auto-m4b-tool.sh"
# cp -u /auto-m4b-tool.sh /temp/mp3merge/auto-m4b-tool.sh

# Set the command prefix if PUID is set
cmd_prefix=""
if [ -n "${PUID}" ]; then
  cmd_prefix="/sbin/setuser ${user_name}"
fi

# Execute the main script with the appropriate user and log output
${cmd_prefix} /auto-m4b-tool.sh 2> /config/auto-m4b-tool.log
