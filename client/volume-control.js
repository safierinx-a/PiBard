#!/usr/bin/env node

/**
 * PiBard Client Volume Control Service
 * Listens for MQTT commands and adjusts audio volume locally
 */

const mqtt = require("mqtt");
const { exec } = require("child_process");
const { promisify } = require("util");
const os = require("os");

const execAsync = promisify(exec);

// Configuration
const MQTT_HOST = process.env.MQTT_HOST || "192.168.1.154";
const MQTT_PORT = process.env.MQTT_PORT || 1883;
const MQTT_USER = process.env.MQTT_USER || "homeassistant";
const MQTT_PASSWORD = process.env.MQTT_PASSWORD || "potato";
const MQTT_TOPIC_PREFIX = "pibard";

// Get hostname to use as client ID
const hostname = os.hostname();
const clientId = process.env.CLIENT_ID || hostname;

console.log(`Starting PiBard volume control for client: ${clientId}`);

// Connect to MQTT broker
const mqttClient = mqtt.connect(`mqtt://${MQTT_HOST}:${MQTT_PORT}`, {
  username: MQTT_USER,
  password: MQTT_PASSWORD,
  clientId: `pibard-client-${clientId}`,
});

mqttClient.on("connect", () => {
  console.log("Connected to MQTT broker");

  // Subscribe to commands for this client
  const commandTopic = `${MQTT_TOPIC_PREFIX}/clients/${clientId}/command`;
  mqttClient.subscribe(commandTopic);
  console.log(`Subscribed to ${commandTopic}`);

  // Announce presence
  publishStatus({ status: "online", client: clientId });
});

mqttClient.on("message", async (topic, message) => {
  try {
    console.log(`Received message on ${topic}: ${message.toString()}`);
    const command = JSON.parse(message.toString());

    if (command.action === "setVolume") {
      await setVolume(command.speaker, command.volume);
      publishStatus({
        status: "success",
        action: "setVolume",
        speaker: command.speaker,
        volume: command.volume,
      });
    } else {
      console.log(`Unknown command: ${command.action}`);
      publishStatus({
        status: "error",
        message: `Unknown command: ${command.action}`,
      });
    }
  } catch (error) {
    console.error("Error processing message:", error);
    publishStatus({
      status: "error",
      message: error.message,
    });
  }
});

// Set volume using pactl
async function setVolume(speakerId, volume) {
  const sinkName = `speaker${speakerId}`;
  const volumeValue = `${volume}%`;

  console.log(`Setting ${sinkName} volume to ${volumeValue}`);
  await execAsync(`pactl set-sink-volume ${sinkName} ${volumeValue}`);
}

// Publish status back to server
function publishStatus(status) {
  const responseTopic = `${MQTT_TOPIC_PREFIX}/clients/${clientId}/response`;
  mqttClient.publish(responseTopic, JSON.stringify(status));
}

// Handle shutdown
process.on("SIGINT", () => {
  console.log("Shutting down...");
  publishStatus({ status: "offline", client: clientId });

  // Allow time for the message to be sent
  setTimeout(() => {
    mqttClient.end();
    process.exit(0);
  }, 500);
});

// Also handle SIGTERM for systemd
process.on("SIGTERM", () => {
  console.log("Received SIGTERM, shutting down...");
  publishStatus({ status: "offline", client: clientId });

  setTimeout(() => {
    mqttClient.end();
    process.exit(0);
  }, 500);
});
