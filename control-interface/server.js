const express = require("express");
const http = require("http");
const socketIo = require("socket.io");
const { SnapcastClient } = require("node-snapcast-client");
const { exec } = require("child_process");
const { promisify } = require("util");

const execAsync = promisify(exec);

// Initialize Express
const app = express();
const server = http.createServer(app);
const io = socketIo(server);

// Snapcast client configuration
const snapcastConfig = {
  host: process.env.SNAPCAST_HOST || "localhost",
  port: process.env.SNAPCAST_PORT || 1705,
};

// Initialize Snapcast client
const snapcast = new SnapcastClient(snapcastConfig);

// Cache for client SSH connections
const clientConnections = {};

// Serve static files
app.use(express.static("public"));

// API routes
app.get("/api/clients", async (req, res) => {
  try {
    const status = await snapcast.getStatus();
    res.json(status.server.groups);
  } catch (error) {
    console.error("Error fetching clients:", error);
    res.status(500).json({ error: "Failed to fetch clients" });
  }
});

app.get("/api/streams", async (req, res) => {
  try {
    const status = await snapcast.getStatus();
    res.json(status.server.streams);
  } catch (error) {
    console.error("Error fetching streams:", error);
    res.status(500).json({ error: "Failed to fetch streams" });
  }
});

// Speaker control API
app.post(
  "/api/speakers/:clientId/:speakerId/volume",
  express.json(),
  async (req, res) => {
    const { clientId, speakerId } = req.params;
    const { volume } = req.body;

    try {
      const clientInfo = await getClientInfo(clientId);
      if (!clientInfo) {
        throw new Error(`Client ${clientId} not found`);
      }

      // Use pactl to set volume
      const sinkName = `speaker${speakerId}`;
      const volumeValue = `${volume}%`;

      // Execute pactl command over SSH
      const cmd = `ssh ${clientInfo.host} "pactl set-sink-volume ${sinkName} ${volumeValue}"`;
      await execAsync(cmd);

      res.json({ success: true });
    } catch (error) {
      console.error(`Error setting speaker volume: ${error}`);
      res.status(500).json({ error: "Failed to set speaker volume" });
    }
  }
);

// Helper function to get client info from Snapcast
async function getClientInfo(clientId) {
  const status = await snapcast.getStatus();
  for (const group of status.server.groups) {
    for (const client of group.clients) {
      if (client.id === clientId) {
        return {
          host: client.host,
          name: client.config.name,
        };
      }
    }
  }
  return null;
}

// Socket.IO for real-time updates
io.on("connection", (socket) => {
  console.log("Client connected");

  // Set up event handlers
  socket.on("setVolume", async (data) => {
    try {
      await snapcast.setClientVolume(data.clientId, {
        volume: data.volume,
        muted: data.muted,
      });
    } catch (error) {
      console.error("Error setting volume:", error);
    }
  });

  socket.on("setStream", async (data) => {
    try {
      await snapcast.setClientStream(data.clientId, data.streamId);
    } catch (error) {
      console.error("Error setting stream:", error);
    }
  });

  socket.on("disconnect", () => {
    console.log("Client disconnected");
  });
});

// Handle Snapcast server events
snapcast.on("update", (data) => {
  io.emit("serverUpdate", data);
});

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`PiBard Control Server listening on port ${PORT}`);

  // Connect to Snapcast server
  snapcast.connect().catch((err) => {
    console.error("Failed to connect to Snapcast server:", err);
  });
});

// Handle shutdown
process.on("SIGINT", async () => {
  console.log("Shutting down...");

  // Disconnect from Snapcast
  await snapcast.disconnect();

  process.exit(0);
});
