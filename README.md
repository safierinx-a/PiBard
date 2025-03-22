# PiBard: Synchronized Multi-Speaker Audio System

A distributed audio system that sends synchronized audio from an HTPC to multiple Raspberry Pis with attached speakers.

## Features

- Synchronous audio playback across multiple Raspberry Pis
- Support for multiple speakers per Pi with individual volume control
- Stream audio from HTPC and mobile devices (iOS/Android)
- Web and mobile control interfaces
- Low latency audio distribution

## Components

- **Server**: Configuration for the HTPC server
- **Clients**: Setup for Raspberry Pi clients
- **Control Interface**: Web and mobile dashboards for system control
- **Scripts**: Helper scripts for installation and maintenance
- **Docs**: Detailed documentation

## Requirements

- HTPC running Linux
- Multiple Raspberry Pis (Raspberry Pi 3 or newer recommended)
- Wired Ethernet network (for minimal latency)
- USB audio interfaces for Raspberry Pis (optional but recommended)
- Multiple speakers to connect to each Pi

## Quick Setup

### Server (HTPC) Setup

1. Clone this repository to your HTPC:

   ```bash
   git clone https://github.com/yourusername/PiBard.git
   cd PiBard
   ```

2. Run the server setup script:

   ```bash
   sudo ./scripts/setup-server.sh
   ```

3. Note your HTPC's IP address for client setup.

### Client (Raspberry Pi) Setup

1. Clone this repository to each Raspberry Pi:

   ```bash
   git clone https://github.com/yourusername/PiBard.git
   cd PiBard
   ```

2. Run the client setup script:

   ```bash
   sudo ./scripts/setup-client.sh
   ```

3. Follow the prompts to enter your HTPC's IP address, client name, and number of speakers.

4. Repeat for each Raspberry Pi in your system.

### Using the Control Interface

Access the control interface at:

- http://[HTPC-IP]:3000

For detailed instructions, see the [Installation Guide](docs/installation.md).

## Architecture

PiBard uses Snapcast as the core technology for synchronized audio streaming, with additional components for enhanced control:

```
Audio Sources → HTPC (Snapserver) → Network → Raspberry Pis (Snapclients) → Speakers
                      ↑
                      └── Control Interface (Web/Mobile)
```

## License

MIT
