// PiBard Control Interface JavaScript

// Connect to the Socket.IO server
const socket = io();

// Client state
let clientsData = [];
let streamsData = {};
let speakersData = {};
const speakersPerClient = new Map(); // Tracks number of speakers for each client

// DOM elements
const clientsContainer = document.getElementById("clients-container");
const sourceSelect = document.getElementById("source-select");
const clientTemplate = document.getElementById("client-template");
const speakerTemplate = document.getElementById("speaker-template");

// Initialize the application
async function init() {
  try {
    // Fetch client and stream data
    await fetchClients();
    await fetchStreams();

    // Render the interface
    renderClients();

    // Set up event listeners
    sourceSelect.addEventListener("change", handleSourceChange);

    // Setup socket event listeners
    socket.on("serverUpdate", handleServerUpdate);
  } catch (error) {
    console.error("Initialization error:", error);
    clientsContainer.innerHTML = `<p class="error">Error connecting to server: ${error.message}</p>`;
  }
}

// Fetch clients from the server
async function fetchClients() {
  const response = await fetch("/api/clients");
  if (!response.ok) {
    throw new Error("Failed to fetch clients");
  }
  const data = await response.json();
  clientsData = [];

  // Extract clients from all groups
  data.forEach((group) => {
    group.clients.forEach((client) => {
      clientsData.push({
        id: client.id,
        name: client.config.name || client.host,
        host: client.host,
        volume: client.config.volume.percent,
        muted: client.config.volume.muted,
        group: group.id,
        // Default to 2 speakers per client
        speakerCount: speakersPerClient.get(client.id) || 2,
      });
    });
  });

  return clientsData;
}

// Fetch available streams
async function fetchStreams() {
  const response = await fetch("/api/streams");
  if (!response.ok) {
    throw new Error("Failed to fetch streams");
  }
  const data = await response.json();
  streamsData = data;

  // Update source select dropdown
  sourceSelect.innerHTML = "";
  Object.keys(data).forEach((streamId) => {
    const stream = data[streamId];
    const option = document.createElement("option");
    option.value = streamId;
    option.textContent = stream.properties.name || streamId;
    sourceSelect.appendChild(option);
  });

  return streamsData;
}

// Render client cards
function renderClients() {
  // Clear existing content
  clientsContainer.innerHTML = clientsData.length
    ? ""
    : "<p>No clients connected</p>";

  // Render each client
  clientsData.forEach((client) => {
    // Clone the template
    const clientCard = document.importNode(clientTemplate.content, true);

    // Set client info
    const cardElement = clientCard.querySelector(".client-card");
    cardElement.dataset.clientId = client.id;

    // Set client name
    cardElement.querySelector(".client-name").textContent = client.name;

    // Set up volume slider
    const volumeSlider = cardElement.querySelector(".volume-slider");
    const volumeValue = cardElement.querySelector(".volume-value");
    volumeSlider.value = client.volume;
    volumeValue.textContent = `${client.volume}%`;

    // Set up mute button
    const muteButton = cardElement.querySelector(".mute-button");
    if (client.muted) {
      muteButton.classList.add("muted");
      muteButton.textContent = "Unmute";
    }

    // Set up event listeners
    volumeSlider.addEventListener("input", (event) => {
      const value = event.target.value;
      volumeValue.textContent = `${value}%`;
      setClientVolume(client.id, value, client.muted);
    });

    muteButton.addEventListener("click", () => {
      const newMuted = !client.muted;
      client.muted = newMuted;
      setClientVolume(client.id, client.volume, newMuted);
      if (newMuted) {
        muteButton.classList.add("muted");
        muteButton.textContent = "Unmute";
      } else {
        muteButton.classList.remove("muted");
        muteButton.textContent = "Mute";
      }
    });

    // Render speaker controls
    const speakersContainer = cardElement.querySelector(".speakers-container");
    renderSpeakers(client, speakersContainer);

    // Add the client card to the container
    clientsContainer.appendChild(clientCard);
  });
}

// Render speakers for a client
function renderSpeakers(client, container) {
  container.innerHTML = "";

  // Create a heading
  const heading = document.createElement("h4");
  heading.textContent = "Individual Speaker Control";
  container.appendChild(heading);

  // Add speakers
  for (let i = 1; i <= client.speakerCount; i++) {
    // Clone the template
    const speakerControl = document.importNode(speakerTemplate.content, true);
    const speakerElement = speakerControl.querySelector(".speaker-control");
    speakerElement.dataset.speakerId = i;

    // Set speaker name
    speakerElement.querySelector(".speaker-name").textContent = `Speaker ${i}`;

    // Get or set default volume
    const speakerId = `${client.id}_speaker${i}`;
    if (!speakersData[speakerId]) {
      speakersData[speakerId] = {
        volume: 70,
        muted: false,
      };
    }

    // Set up volume slider
    const volumeSlider = speakerElement.querySelector(".speaker-volume-slider");
    const volumeValue = speakerElement.querySelector(".speaker-volume-value");
    volumeSlider.value = speakersData[speakerId].volume;
    volumeValue.textContent = `${speakersData[speakerId].volume}%`;

    // Set up mute button
    const muteButton = speakerElement.querySelector(".speaker-mute-button");
    if (speakersData[speakerId].muted) {
      muteButton.classList.add("muted");
      muteButton.textContent = "Unmute";
    }

    // Set up event listeners
    volumeSlider.addEventListener("input", (event) => {
      const value = event.target.value;
      volumeValue.textContent = `${value}%`;
      setSpeakerVolume(client.id, i, value);
    });

    muteButton.addEventListener("click", () => {
      const speakerId = `${client.id}_speaker${i}`;
      const newMuted = !speakersData[speakerId].muted;
      speakersData[speakerId].muted = newMuted;
      if (newMuted) {
        muteButton.classList.add("muted");
        muteButton.textContent = "Unmute";
        // Set volume to 0 when muted
        setSpeakerVolume(client.id, i, 0);
      } else {
        muteButton.classList.remove("muted");
        muteButton.textContent = "Mute";
        // Restore volume when unmuted
        setSpeakerVolume(client.id, i, speakersData[speakerId].volume);
      }
    });

    container.appendChild(speakerControl);
  }
}

// Set client volume
function setClientVolume(clientId, volume, muted) {
  socket.emit("setVolume", {
    clientId,
    volume: parseInt(volume),
    muted,
  });
}

// Set speaker volume
async function setSpeakerVolume(clientId, speakerId, volume) {
  const speakerKey = `${clientId}_speaker${speakerId}`;
  speakersData[speakerKey].volume = parseInt(volume);

  try {
    const response = await fetch(
      `/api/speakers/${clientId}/${speakerId}/volume`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          volume: parseInt(volume),
        }),
      }
    );

    if (!response.ok) {
      throw new Error("Failed to set speaker volume");
    }
  } catch (error) {
    console.error("Error setting speaker volume:", error);
  }
}

// Handle audio source change
function handleSourceChange(event) {
  const streamId = event.target.value;
  // Change the stream for all clients
  clientsData.forEach((client) => {
    socket.emit("setStream", {
      clientId: client.id,
      streamId,
    });
  });
}

// Handle server updates via socket
function handleServerUpdate(data) {
  console.log("Server update received:", data);
  // Refresh our data and UI
  fetchClients().then(() => {
    renderClients();
  });
}

// Initialize the app
window.addEventListener("DOMContentLoaded", init);
