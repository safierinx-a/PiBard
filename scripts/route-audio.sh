#!/bin/bash
#
# PiBard Audio Routing Script
#

# Function to list available sinks
list_sinks() {
    echo "Available audio sinks:"
    wpctl status | grep "Sink" -A 10
}

# Function to route all audio to Snapcast
route_to_snapcast() {
    echo "Routing all audio to Snapcast..."
    wpctl set-default $(wpctl status | grep "snapcast_input" | cut -d "." -f1)
}

# Function to restore default audio
restore_default() {
    echo "Restoring default audio output..."
    wpctl set-default $(wpctl status | grep "Built-in" | head -n1 | cut -d "." -f1)
}

# Show usage if no arguments provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  list     - List available audio sinks"
    echo "  snapcast - Route all system audio to Snapcast"
    echo "  default  - Restore default audio output"
    exit 1
fi

# Process commands
case "$1" in
    "list")
        list_sinks
        ;;
    "snapcast")
        route_to_snapcast
        ;;
    "default")
        restore_default
        ;;
    *)
        echo "Unknown command: $1"
        exit 1
        ;;
esac 