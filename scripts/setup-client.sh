#!/bin/bash
#
# PiBard Client Setup Script
# This script installs and configures a Raspberry Pi as a PiBard client
#

# Exit on error
set -e

echo "==================================================================="
echo "PiBard Client Setup Script"
echo "This script will install and configure Snapcast client and"
echo "per-speaker control on your Raspberry Pi."
echo "==================================================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo"
  exit 1
fi

# Configuration
read -p "Enter your HTPC server IP address: " SERVER_IP
read -p "Enter a name for this client (e.g., livingroom, kitchen): " CLIENT_NAME
read -p "How many speakers are connected to this Pi? [1-3]: " SPEAKER_COUNT

# Validate speaker count
if ! [[ "$SPEAKER_COUNT" =~ ^[1-3]$ ]]; then
    echo "Invalid speaker count. Using default of 2 speakers."
    SPEAKER_COUNT=2
fi

echo "Step 1: Installing required dependencies..."
apt update
apt install -y snapclient pulseaudio pulseaudio-utils alsa-utils \
  pulseaudio-module-zeroconf libasound2-plugins

echo "Step 2: Creating necessary directories..."
mkdir -p /etc/pulse

echo "Step 3: Backing up existing configurations..."
[ -f /etc/pulse/default.pa ] && cp /etc/pulse/default.pa /etc/pulse/default.pa.bak
[ -f /etc/pulse/client.conf ] && cp /etc/pulse/client.conf /etc/pulse/client.conf.bak
[ -f /etc/asound.conf ] && cp /etc/asound.conf /etc/asound.conf.bak

echo "Step 4: Copying and customizing PiBard client configurations..."
# Copy initial PulseAudio configuration
cp clients/configs/pulse-default.pa /etc/pulse/default.pa

# Configure PulseAudio for the correct number of speakers
if [ "$SPEAKER_COUNT" -eq 1 ]; then
    # Remove speaker2 and speaker3 configuration
    sed -i '/speaker2/,+2d' /etc/pulse/default.pa
    sed -i '/speaker3/,+1d' /etc/pulse/default.pa
    sed -i '/source=snapcast_sink.monitor sink=speaker2/d' /etc/pulse/default.pa
    sed -i '/source=snapcast_sink.monitor sink=speaker3/d' /etc/pulse/default.pa
elif [ "$SPEAKER_COUNT" -eq 3 ]; then
    # Uncomment speaker3 configuration
    sed -i 's/#load-module module-remap-sink sink_name=speaker3/load-module module-remap-sink sink_name=speaker3/' /etc/pulse/default.pa
    sed -i 's/#load-module module-loopback source=snapcast_sink.monitor sink=speaker3/load-module module-loopback source=snapcast_sink.monitor sink=speaker3/' /etc/pulse/default.pa
fi

# Set up client PulseAudio config
cat > /etc/pulse/client.conf << EOL
default-server = localhost
autospawn = yes
daemon-binary = /usr/bin/pulseaudio
extra-arguments = --log-target=syslog
cookie-file = /tmp/pulse-cookie
enable-shm = yes
EOL

# Set up ALSA config to use PulseAudio
cat > /etc/asound.conf << EOL
pcm.!default {
    type pulse
    hint.description "Default Audio Device"
}

ctl.!default {
    type pulse
}
EOL

echo "Step 5: Creating Snapclient startup script..."
# Customize and copy the start script
sed -i "s/CLIENT_NAME=\"livingroom\"/CLIENT_NAME=\"$CLIENT_NAME\"/" clients/scripts/start-snapclient.sh
sed -i "s/SERVER_IP=\"192.168.1.100\"/SERVER_IP=\"$SERVER_IP\"/" clients/scripts/start-snapclient.sh
cp clients/scripts/start-snapclient.sh /usr/local/bin/
chmod +x /usr/local/bin/start-snapclient.sh

echo "Step 6: Setting up services..."
# Copy and customize systemd service
cp clients/configs/snapclient.service /etc/systemd/system/

# Modify the service to use the local user instead of hardcoded "pi"
CURRENT_USER=$(logname)
sed -i "s/User=pi/User=$CURRENT_USER/" /etc/systemd/system/snapclient.service

# Enable and start services
systemctl enable snapclient
systemctl restart snapclient

echo "Step 7: Configuring PulseAudio to start at boot..."
# Create systemd service for PulseAudio
cat > /etc/systemd/system/pulseaudio.service << EOL
[Unit]
Description=PulseAudio Sound System
Before=sound.target

[Service]
Type=simple
User=$CURRENT_USER
ExecStart=/usr/bin/pulseaudio --system --disallow-exit --disallow-module-loading
Restart=always

[Install]
WantedBy=multi-user.target
EOL

systemctl enable pulseaudio
systemctl start pulseaudio

echo "Step 8: Setting PulseAudio permissions..."
usermod -a -G audio $CURRENT_USER
usermod -a -G pulse $CURRENT_USER
usermod -a -G pulse-access $CURRENT_USER

echo "Step 9: Creating speaker test script..."
cat > /usr/local/bin/test-speakers.sh << EOL
#!/bin/bash
echo "Testing PiBard speakers..."
for i in \$(seq 1 $SPEAKER_COUNT); do
    echo "Playing test tone on speaker \$i..."
    paplay --device=speaker\$i /usr/share/sounds/alsa/Front_Center.wav
    sleep 1
done
echo "Speaker test complete."
EOL
chmod +x /usr/local/bin/test-speakers.sh

echo "==================================================================="
echo "PiBard client installation complete!"
echo ""
echo "Client information:"
echo " - Name: $CLIENT_NAME"
echo " - Connected to server: $SERVER_IP"
echo " - Number of speakers: $SPEAKER_COUNT"
echo ""
echo "Your Raspberry Pi will now connect to the PiBard server and"
echo "stream audio to your speakers."
echo ""
echo "To test your speakers, run: sudo /usr/local/bin/test-speakers.sh"
echo ""
echo "To view client status: sudo systemctl status snapclient"
echo ""
echo "Note: You may need to reboot for all changes to take effect"
echo "===================================================================" 