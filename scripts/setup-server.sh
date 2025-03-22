#!/bin/bash
#
# PiBard Server Setup Script
# This script installs and configures the HTPC server for PiBard
#

# Exit on error
set -e

echo "==================================================================="
echo "PiBard Server Setup Script"
echo "This script will install and configure the Snapcast server and"
echo "audio streaming components on your HTPC."
echo "==================================================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo"
  exit 1
fi

echo "Step 1: Installing required dependencies..."
apt update
apt install -y snapserver pulseaudio pulseaudio-utils alsa-utils \
  pulseaudio-module-zeroconf pulseaudio-module-bluetooth \
  shairport-sync pulseaudio-dlna bluetooth bluez \
  libasound2-plugins libbluetooth3 bluez-tools \
  nodejs npm

echo "Step 2: Creating necessary directories..."
mkdir -p /etc/snapserver
mkdir -p /etc/pulse

echo "Step 3: Backing up existing configurations..."
[ -f /etc/snapserver.conf ] && cp /etc/snapserver.conf /etc/snapserver.conf.bak
[ -f /etc/pulse/default.pa ] && cp /etc/pulse/default.pa /etc/pulse/default.pa.bak

echo "Step 4: Copying PiBard server configurations..."
cp server/configs/snapserver.conf /etc/snapserver.conf
cp server/configs/pulse-default.pa /etc/pulse/default.pa

echo "Step 5: Setting up audio pipe for streaming..."
FIFO_FILE="/tmp/snapfifo"
if [ ! -p "$FIFO_FILE" ]; then
    mkfifo "$FIFO_FILE"
fi
chmod 777 "$FIFO_FILE"

echo "Step 6: Installing and configuring the control interface..."
cd control-interface
npm install
npm run build
mkdir -p /usr/share/snapserver/snapweb
cp -r public/* /usr/share/snapserver/snapweb/
cd ..

echo "Step 7: Setting up services..."
systemctl enable snapserver
systemctl restart snapserver
systemctl restart pulseaudio || pulseaudio -k && pulseaudio --start

echo "Step 8: Setting up the control interface server as a service..."
cat > /etc/systemd/system/pibard-control.service << EOL
[Unit]
Description=PiBard Control Interface
After=network.target snapserver.service

[Service]
ExecStart=/usr/bin/node $(pwd)/control-interface/server.js
WorkingDirectory=$(pwd)/control-interface
Restart=always
User=$(logname)
Environment=PORT=3000 SNAPCAST_HOST=localhost SNAPCAST_PORT=1705

[Install]
WantedBy=multi-user.target
EOL

systemctl enable pibard-control
systemctl start pibard-control

echo "Step 9: Configuring firewall (if installed)..."
if command -v ufw > /dev/null; then
    ufw allow 1704/tcp comment "Snapcast TCP"
    ufw allow 1704/udp comment "Snapcast UDP"
    ufw allow 1705/tcp comment "Snapcast Control"
    ufw allow 1780/tcp comment "Snapcast Web"
    ufw allow 3000/tcp comment "PiBard Control"
    ufw allow 5353/udp comment "mDNS"
fi

SERVER_IP=$(hostname -I | cut -d' ' -f1)

echo "==================================================================="
echo "PiBard server installation complete!"
echo ""
echo "Your server is now configured with the following services:"
echo " - Snapcast server (audio streaming)"
echo " - PulseAudio (audio processing)"
echo " - Shairport-sync (AirPlay receiver)"
echo " - PulseAudio-DLNA (DLNA/UPnP receiver)"
echo " - Bluetooth Audio (Bluetooth A2DP receiver)"
echo " - PiBard Control Interface (volume/speaker control)"
echo ""
echo "Access the web control interface at:"
echo " - Snapcast web interface: http://$SERVER_IP:1780"
echo " - PiBard control interface: http://$SERVER_IP:3000"
echo ""
echo "Important: Make note of your server IP ($SERVER_IP) for client setup"
echo "===================================================================" 