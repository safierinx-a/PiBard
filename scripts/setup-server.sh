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
apt install -y snapserver pipewire pipewire-pulse pipewire-audio-client-libraries \
  alsa-utils shairport-sync bluetooth bluez bluealsa \
  libasound2-plugins libbluetooth3 bluez-tools \
  nodejs npm

echo "Step 2: Creating necessary directories..."
mkdir -p /etc/snapserver
mkdir -p /var/run/snapserver
mkdir -p /var/lib/snapserver
mkdir -p /usr/share/snapserver/snapweb

# Ensure we have the official Snapcast web interface
if [ ! -f /usr/share/snapserver/snapweb/index.html ]; then
    echo "Downloading official Snapcast web interface..."
    apt install -y git
    TMP_DIR=$(mktemp -d)
    git clone --depth 1 https://github.com/badaix/snapweb.git "$TMP_DIR"
    cp -r "$TMP_DIR/dist/"* /usr/share/snapserver/snapweb/
    rm -rf "$TMP_DIR"
fi

echo "Step 3: Setting correct permissions..."
chown -R _snapserver:_snapserver /var/run/snapserver /var/lib/snapserver

echo "Step 4: Copying PiBard server configurations..."
cp server/configs/snapserver.conf /etc/snapserver.conf

echo "Step 5: Setting up audio pipe for streaming..."
FIFO_FILE="/tmp/snapfifo"
if [ ! -p "$FIFO_FILE" ]; then
    mkfifo "$FIFO_FILE"
fi
chmod 777 "$FIFO_FILE"

# Ensure FIFO access works with newer kernels
echo "Configuring kernel security settings for FIFO access..."
if grep -q "fs.protected_fifos" /etc/sysctl.conf; then
    sed -i 's/fs.protected_fifos=.*/fs.protected_fifos=0/' /etc/sysctl.conf
else
    echo "fs.protected_fifos=0" >> /etc/sysctl.conf
fi
sysctl -p

echo "Step 6: Installing and configuring the control interface..."
cd control-interface
npm install
npm run build
cp -r public/* /usr/share/snapserver/snapweb/
cd ..

echo "Step 7: Configuring firewall (if installed)..."
if command -v ufw > /dev/null; then
    ufw allow 1704/tcp comment "Snapcast TCP"
    ufw allow 1704/udp comment "Snapcast UDP"
    ufw allow 1705/tcp comment "Snapcast Control"
    ufw allow 1780/tcp comment "Snapcast Web"
    ufw allow 3000/tcp comment "PiBard Control"
    ufw allow 5353/udp comment "mDNS"
fi

echo "Step 8: Setting up services..."
# Create systemd service file
cat > /usr/lib/systemd/system/snapserver.service << EOL
[Unit]
Description=Snapcast server
Documentation=man:snapserver(1)
Wants=network-online.target avahi-daemon.service
After=network-online.target time-sync.target avahi-daemon.service

[Service]
EnvironmentFile=-/etc/default/snapserver
ExecStart=/usr/bin/snapserver --logging.sink=system \$SNAPSERVER_OPTS
User=_snapserver
Group=_snapserver
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL

# Enable and start services
systemctl daemon-reload
systemctl enable snapserver
systemctl restart snapserver

# Restart PipeWire services for the actual user
ACTUAL_USER=$(logname)
ACTUAL_UID=$(id -u $ACTUAL_USER)
export XDG_RUNTIME_DIR=/run/user/$ACTUAL_UID
su - $ACTUAL_USER -c 'export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"; systemctl --user restart pipewire pipewire-pulse'

echo "Step 9: Setting up the control interface server as a service..."
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

SERVER_IP=$(hostname -I | cut -d' ' -f1)

echo "==================================================================="
echo "PiBard server installation complete!"
echo ""
echo "Your server is now configured with the following services:"
echo " - Snapcast server (audio streaming)"
echo " - PipeWire (audio processing)"
echo " - Shairport-sync (AirPlay receiver)"
echo " - Bluetooth Audio (Bluetooth A2DP receiver)"
echo " - PiBard Control Interface (volume/speaker control)"
echo ""
echo "Access the web control interface at:"
echo " - Snapcast web interface: http://$SERVER_IP:1780"
echo " - PiBard control interface: http://$SERVER_IP:3000"
echo ""
echo "IMPORTANT: Remote volume control requires SSH key-based authentication"
echo "to your Raspberry Pi clients. Make sure you set up SSH keys with:"
echo "  ssh-keygen -t ed25519"
echo "  ssh-copy-id pi@<client-ip-address>"
echo ""
echo "Important: Make note of your server IP ($SERVER_IP) for client setup"
echo "===================================================================" 