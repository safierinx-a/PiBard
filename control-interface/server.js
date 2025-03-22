const express = require("express");
const http = require("http");
const socketIo = require("socket.io");
const fetch = require("node-fetch");
const { exec } = require("child_process");
const { promisify } = require("util");

const execAsync = promisify(exec);

// Initialize Express
const app = express();
const server = http.createServer(app);
const io = socketIo(server);

// Snapcast configuration
const SNAPCAST_HOST = process.env.SNAPCAST_HOST || "localhost";
const SNAPCAST_PORT = process.env.SNAPCAST_PORT || 1705;
const SNAPCAST_API = `http://${SNAPCAST_HOST}:${SNAPCAST_PORT}/jsonrpc`;

// Helper function for Snapcast API calls
async function snapcastRequest(method, params = {}) {
  const response = await fetch(SNAPCAST_API, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      id: Date.now(),
      jsonrpc: "2.0",
      method,
      params,
    }),
  });

  if (!response.ok) {
    throw new Error(`Snapcast API error: ${response.statusText}`);
  }

  const data = await response.json();
  if (data.error) {
    throw new Error(`Snapcast API error: ${data.error.message}`);
  }

  return data.result;
}

// Serve static files
app.use(express.static("public"));

// API routes
app.get("/api/clients", async (req, res) => {
  try {
    const status = await snapcastRequest("Server.GetStatus");
    res.json(status.server.groups);
  } catch (error) {
    console.error("Error fetching clients:", error);
    res.status(500).json({ error: "Failed to fetch clients" });
  }
});

app.get("/api/streams", async (req, res) => {
  try {
    const status = await snapcastRequest("Server.GetStatus");
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

// Helper function to get client info
async function getClientInfo(clientId) {
  const status = await snapcastRequest("Server.GetStatus");
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
      await snapcastRequest("Client.SetVolume", {
        id: data.clientId,
        volume: {
          percent: data.volume,
          muted: data.muted,
        },
      });
    } catch (error) {
      console.error("Error setting volume:", error);
    }
  });

  socket.on("setStream", async (data) => {
    try {
      await snapcastRequest("Client.SetStream", {
        id: data.clientId,
        stream_id: data.streamId,
      });
    } catch (error) {
      console.error("Error setting stream:", error);
    }
  });

  socket.on("disconnect", () => {
    console.log("Client disconnected");
  });
});

// Start server
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`PiBard Control Server listening on port ${PORT}`);
});

// Handle shutdown
process.on("SIGINT", () => {
  console.log("Shutting down...");
  process.exit(0);
});
