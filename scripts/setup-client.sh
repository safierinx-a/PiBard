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
read -p "Enter your MQTT broker IP address [192.168.1.154]: " MQTT_IP
MQTT_IP=${MQTT_IP:-192.168.1.154}
read -p "Enter your MQTT username [homeassistant]: " MQTT_USER
MQTT_USER=${MQTT_USER:-homeassistant}
read -p "Enter your MQTT password [potato]: " MQTT_PASSWORD
MQTT_PASSWORD=${MQTT_PASSWORD:-potato}

# Validate speaker count
if ! [[ "$SPEAKER_COUNT" =~ ^[1-3]$ ]]; then
    echo "Invalid speaker count. Using default of 2 speakers."
    SPEAKER_COUNT=2
fi

echo "Step 1: Installing required dependencies..."
apt update
apt install -y snapclient pipewire pipewire-pulse pipewire-audio-client-libraries \
  alsa-utils libasound2-plugins nodejs npm wireplumber

echo "Step 2: Creating necessary directories..."
mkdir -p /etc/pipewire
mkdir -p /opt/pibard

echo "Step 3: Backing up existing configurations..."
[ -f /etc/pipewire/pipewire.conf ] && cp /etc/pipewire/pipewire.conf /etc/pipewire/pipewire.conf.bak
[ -f /etc/asound.conf ] && cp /etc/asound.conf /etc/asound.conf.bak

echo "Step 4: Copying and customizing PiBard client configurations..."
# Check if PipeWire configuration exists
if [ -f clients/configs/pipewire-default.conf ]; then
    # Copy initial PipeWire configuration
    cp clients/configs/pipewire-default.conf /etc/pipewire/pipewire.conf
else
    # Create a minimal PipeWire configuration
    cat > /etc/pipewire/pipewire.conf << EOL
# PipeWire configuration file for PiBard clients
#
# This configuration sets up virtual sinks for multiple speakers
#

context.properties = {
    default.clock.rate = 48000
    default.clock.quantum = 1024
    default.clock.min-quantum = 32
    default.clock.max-quantum = 8192
}

context.modules = [
    # Core modules
    { name = libpipewire-module-rt
        args = {
            nice.level = -11
        }
    }
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-adapter }
    { name = libpipewire-module-metadata }

    # Main snapcast sink
    { name = libpipewire-module-loopback
        args = {
            node.name = "snapcast_sink"
            capture.props = {
                media.class = "Audio/Sink"
                node.name = "snapcast_sink"
                node.description = "Snapcast Audio"
            }
            playback.props = {
                node.name = "snapcast_playback"
                media.class = "Audio/Source"
                audio.position = [ FL FR ]
            }
        }
    }

    # Speaker 1
    { name = libpipewire-module-loopback
        args = {
            node.name = "speaker1_loopback"
            capture.props = {
                media.class = "Audio/Sink"
                node.name = "speaker1"
                node.description = "Speaker 1"
                audio.position = [ FL FR ]
            }
            playback.props = {
                media.class = "Audio/Source"
                node.name = "speaker1_out"
                audio.position = [ FL FR ]
                node.target = "alsa_output.platform-bcm2835_audio.stereo-fallback"
            }
        }
    }

    # Speaker 2
    { name = libpipewire-module-loopback
        args = {
            node.name = "speaker2_loopback"
            capture.props = {
                media.class = "Audio/Sink"
                node.name = "speaker2"
                node.description = "Speaker 2"
                audio.position = [ FL FR ]
            }
            playback.props = {
                media.class = "Audio/Source"
                node.name = "speaker2_out"
                audio.position = [ FL FR ]
                node.target = "alsa_output.platform-soc_audio.stereo-fallback"
            }
        }
    }

    # Connect snapcast sink to all speakers
    { name = libpipewire-module-loopback
        args = {
            capture.props = {
                media.class = "Audio/Source"
                node.name = "snapcast_to_speaker1"
                source = "snapcast_sink.monitor"
            }
            playback.props = {
                media.class = "Audio/Sink"
                node.name = "speaker1_in"
                node.target = "speaker1"
            }
        }
    }

    { name = libpipewire-module-loopback
        args = {
            capture.props = {
                media.class = "Audio/Source"
                node.name = "snapcast_to_speaker2"
                source = "snapcast_sink.monitor"
            }
            playback.props = {
                media.class = "Audio/Sink"
                node.name = "speaker2_in"
                node.target = "speaker2"
            }
        }
    }
]
EOL
fi

# Configure PipeWire for the correct number of speakers
if [ "$SPEAKER_COUNT" -eq 1 ]; then
    # Remove speaker2 and speaker3 configuration
    sed -i '/speaker2/,+2d' /etc/pipewire/pipewire.conf
    sed -i '/speaker3/,+1d' /etc/pipewire/pipewire.conf
elif [ "$SPEAKER_COUNT" -eq 3 ]; then
    # Uncomment speaker3 configuration
    sed -i 's/#sink_name = "speaker3"/sink_name = "speaker3"/' /etc/pipewire/pipewire.conf
    sed -i 's/#source = "snapcast_sink.monitor"/source = "snapcast_sink.monitor"/' /etc/pipewire/pipewire.conf
fi

# Set up ALSA config to use PipeWire
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
sed -i "s|CLIENT_NAME=\"livingroom\"|CLIENT_NAME=\"$CLIENT_NAME\"|" clients/scripts/start-snapclient.sh
sed -i "s|SERVER_IP=\"192.168.1.100\"|SERVER_IP=\"$SERVER_IP\"|" clients/scripts/start-snapclient.sh
cp clients/scripts/start-snapclient.sh /usr/local/bin/
chmod +x /usr/local/bin/start-snapclient.sh

echo "Step 6: Setting up MQTT volume control..."
# Get the current user
CURRENT_USER=$(logname)
CURRENT_UID=$(id -u $CURRENT_USER)

# Copy the volume control script and package.json
cp client/volume-control.js /opt/pibard/
cp client/package.json /opt/pibard/

# Install dependencies
cd /opt/pibard
npm install

# Create and configure the service file
cat > /etc/systemd/system/pibard-volume.service << EOL
[Unit]
Description=PiBard Volume Control Service
After=network.target snapclient.service

[Service]
ExecStart=/usr/bin/node /opt/pibard/volume-control.js
WorkingDirectory=/opt/pibard
Restart=always
User=$CURRENT_USER
Environment=MQTT_HOST=$MQTT_IP
Environment=MQTT_PORT=1883
Environment=MQTT_USER=$MQTT_USER
Environment=MQTT_PASSWORD=$MQTT_PASSWORD
Environment=CLIENT_ID=$CLIENT_NAME

[Install]
WantedBy=multi-user.target
EOL

echo "Step 7: Setting up services..."
# Create the systemd service file directly
cat > /etc/systemd/system/snapclient.service << EOL
[Unit]
Description=Snapcast client
After=network-online.target sound.target
Wants=network-online.target

[Service]
Type=simple
User=pi
ExecStart=/usr/local/bin/start-snapclient.sh
Environment=XDG_RUNTIME_DIR=/run/user/1000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

# Modify the service to use the local user instead of hardcoded "pi"
sed -i "s/User=pi/User=$CURRENT_USER/" /etc/systemd/system/snapclient.service

# Set the correct runtime directory for the user
sed -i "s|Environment=XDG_RUNTIME_DIR=/run/user/1000|Environment=XDG_RUNTIME_DIR=/run/user/$CURRENT_UID|" /etc/systemd/system/snapclient.service

# Fix the CURRENT_USER in volume control service
sed -i "/User=/c\User=$CURRENT_USER" /etc/systemd/system/pibard-volume.service

# Enable and start services
systemctl daemon-reload
systemctl enable snapclient
systemctl restart snapclient
systemctl enable pibard-volume
systemctl start pibard-volume

echo "Step 8: Configuring PipeWire to start at boot..."
# Enable lingering for the user to keep PipeWire running after logout
loginctl enable-linger $CURRENT_USER

# Set up a user-service autostart for PipeWire
mkdir -p /home/$CURRENT_USER/.config/systemd/user/
cat > /home/$CURRENT_USER/.config/systemd/user/pipewire.service << EOL
[Unit]
Description=PipeWire Multimedia Service
After=pipewire-pulse.service

[Service]
ExecStart=/usr/bin/pipewire

[Install]
WantedBy=default.target
EOL

cat > /home/$CURRENT_USER/.config/systemd/user/pipewire-pulse.service << EOL
[Unit]
Description=PipeWire PulseAudio Service

[Service]
ExecStart=/usr/bin/pipewire-pulse

[Install]
WantedBy=default.target
EOL

# Fix permissions
chown -R $CURRENT_USER:$CURRENT_USER /home/$CURRENT_USER/.config

# Use systemctl --global instead of --user
systemctl --global enable pipewire.service pipewire-pulse.service

echo "Step 9: Setting audio permissions..."
usermod -a -G audio $CURRENT_USER

echo "Step 10: Creating speaker test script..."
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
echo " - MQTT broker: $MQTT_IP"
echo " - Number of speakers: $SPEAKER_COUNT"
echo ""
echo "Your Raspberry Pi will now connect to the PiBard server and"
echo "stream audio to your speakers."
echo ""
echo "To test your speakers, run: sudo /usr/local/bin/test-speakers.sh"
echo ""
echo "To view client status: sudo systemctl status snapclient"
echo "To view volume control status: sudo systemctl status pibard-volume"
echo ""
echo "Note: You may need to reboot for all changes to take effect"
echo "===================================================================" 