#!/bin/bash
#
# PiBard Snapclient Startup Script
#

# Client settings - customize these for each Pi
CLIENT_NAME="livingroom"
SERVER_IP="192.168.1.100"  # Replace with your HTPC IP
SOUND_OUTPUT="pulse"        # Use PulseAudio output
LATENCY=0                  # Adjust if needed, 0 = automatic

# Advanced options
BUFFER_MS=1000             # Buffer in ms, increase if audio stutters

# Ensure PulseAudio is running
pulseaudio --start

# Wait for PulseAudio to initialize
sleep 2

# Start snapclient with our settings and connect to server 
snapclient \
  --host "${SERVER_IP}" \
  --soundcard "${SOUND_OUTPUT}" \
  --hostID "${CLIENT_NAME}" \
  --latency ${LATENCY} \
  --buffer ${BUFFER_MS}

# If snapclient exits for any reason, restart PulseAudio and try again
if [ $? -ne 0 ]; then
  echo "Snapclient exited with error, restarting..."
  pulseaudio -k
  sleep 2
  pulseaudio --start
  sleep 2
  
  # Try one more time with safer settings
  snapclient \
    --host "${SERVER_IP}" \
    --soundcard "${SOUND_OUTPUT}" \
    --hostID "${CLIENT_NAME}" \
    --latency 50 \
    --buffer 2000
fi 