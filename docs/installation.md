# PiBard Installation Guide

This guide walks through the complete setup process for the PiBard synchronized audio system.

## 1. HTPC Server Setup

### Prerequisites

- Linux-based HTPC (Ubuntu/Debian recommended)
- Git
- Python 3.7+
- Node.js 14+

### Installation Steps

```bash
# 1. Clone the PiBard repository
git clone https://github.com/yourusername/PiBard.git
cd PiBard

# 2. Install server dependencies
sudo apt update
sudo apt install -y snapserver shairport-sync pulseaudio-dlna bluez-alsa alsa-utils nodejs npm

# 3. Configure Snapcast server
sudo cp server/configs/snapserver.conf /etc/snapserver.conf
sudo systemctl enable snapserver
sudo systemctl restart snapserver

# 4. Set up audio sources
# For system audio capture:
sudo cp server/configs/asound.conf /etc/asound.conf
sudo cp server/configs/pulse-default.pa /etc/pulse/default.pa

# 5. Install the control interface
cd control-interface
npm install
npm run build
sudo cp -r dist/* /usr/share/snapserver/snapweb/

# 6. Start services
sudo systemctl restart snapserver
sudo systemctl restart pulseaudio
```

## 2. Raspberry Pi Client Setup

Repeat these steps for each Raspberry Pi in your system.

### Prerequisites

- Raspberry Pi 3/4 with Raspberry Pi OS (Lite)
- USB Audio Interface (recommended)
- Wired Ethernet connection

### Installation Steps

```bash
# 1. Install client dependencies
sudo apt update
sudo apt install -y snapclient alsa-utils pulseaudio pulseaudio-utils pulseaudio-module-zeroconf

# 2. Set up audio output
sudo cp clients/configs/asound.conf /etc/asound.conf

# 3. Configure PulseAudio for per-speaker control
sudo cp clients/configs/pulse-default.pa /etc/pulse/default.pa
sudo cp clients/configs/pulse-client.conf /etc/pulse/client.conf

# 4. Install client scripts
sudo cp clients/scripts/start-snapclient.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/start-snapclient.sh

# 5. Configure autostart
sudo cp clients/configs/snapclient.service /etc/systemd/system/
sudo systemctl enable snapclient
sudo systemctl start snapclient
```

## 3. Control Interface Setup

### Web Interface

The web interface is automatically installed during the HTPC setup and can be accessed at:

```
http://[HTPC-IP]:1780
```

### Mobile Apps

- Android: Install "Snapcast" from Google Play Store
- iOS: Install "Snapcast Remote" from App Store

Configure the app to connect to your HTPC's IP address.

## 4. Testing Your Setup

1. Play audio on your HTPC (e.g., using VLC, Spotify, etc.)
2. Open the web interface and verify all clients are connected
3. Adjust volumes and grouping to test functionality
4. Try connecting from a mobile device via AirPlay or DLNA

## 5. Troubleshooting

- **No Audio Output**: Check ALSA mixer settings using `alsamixer`
- **Client Not Connecting**: Verify network connectivity and firewall settings
- **Audio Delay**: Adjust latency settings in snapclient
- **Per-Speaker Control Not Working**: Verify PulseAudio channel mapping

See the [Troubleshooting Guide](troubleshooting.md) for more detailed solutions.

## Next Steps

- [Advanced Configuration](advanced-config.md)
- [Control Interface Customization](control-interface.md)
- [Adding Hardware Controllers](hardware-controllers.md)
