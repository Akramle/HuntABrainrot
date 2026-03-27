# Gemini Context: CaptureBrainRots

This file provides architectural guidelines and development context for `CaptureBrainRots`, a Roblox creature collection and tycoon game.

---

## 🏗️ Core Architecture: Service/Controller Framework

The project utilizes a custom **Service/Controller framework** managed by a `ModuleLoader`. This structure separates backend logic (Server) from frontend logic (Client), with shared code residing in `src/Shared`.

### Lifecycle Methods:
All modules (Services and Controllers) can implement the following lifecycle methods:
1.  **`Init(runtime)`**: Called during initial load. Used for setting up internal state, registering remotes, and preparing for cross-module interaction. Execution order is determined by the `Priority` property (lowest first, default 0).
2.  **`Start(runtime)`**: Called after *all* modules have completed their `Init`. Used for starting game loops, connecting to events, and cross-service logic.

### The `runtime` Object:
Passed to both `Init` and `Start`, providing a unified interface:
- **`Config`**: The project's configuration (sanitized on the client).
- **`Remotes`**: Access to the `RemoteRegistry` for networking.
- **`GetService(name)`** (Server) / **`GetController(name)`** (Client): Access to other framework-managed modules.
- **`Player`** (Client only): The `LocalPlayer` instance.

### Project Mapping (`default.project.json`):
The project is managed by **Argon** and maps to Roblox as follows:
- `src/Shared` -> `ReplicatedStorage`
- `src/Server` -> `ServerScriptService`
- `src/Client` -> `StarterPlayer.StarterPlayerScripts`

---

## 📡 Networking & Configuration

### `RemoteRegistry.luau`:
All networking is centralized here. Remotes are lazily created by the server and parented to `ReplicatedStorage.RuntimeRemotes`. The client uses `WaitForChild` via the registry to ensure they exist before use.

### Layered Configuration:
1.  **`GameConfig.luau` (Shared)**: Contains global constants like remote folder names.
2.  **`ServerConfig.luau` (Server)**: Contains sensitive data and balancing constants (animal stats, spawn pools, admin IDs).
3.  **`ConfigService`**: Upon client startup, it fetches a **sanitized** subset of `ServerConfig` to be used for UI and local logic.

---

## 🐾 Core Game Systems

### Animal System (`AnimalService.luau`):
- **Capture**: Reducing wild animal health allows players to capture them into their inventory (as tools).
- **Mutations**: Revenue multipliers and visual effects (e.g., `Gold`, `Malevolent`, `Soaked`).
- **Rarity**: Scales stats and revenue from Common to Devine.

### Base/Tycoon System (`BaseService.luau`):
- **Pads**: Animals are placed on pads to generate "Bucks" (passive income).
- **Stealing**: A unique mechanic where players can pay to "steal" animals from other players' bases.

### Event System (`EventService.luau`):
- Periodic server-wide events (Rain, Tornado, Abduction) that modify animal stats and apply mutations.

---

## 🛠️ Development & Tooling

### Building and Syncing:
- **Build Place**: `argon build`
- **Sync to Studio**: `argon serve` (Ensure Argon plugin is active in Roblox Studio).

### Coding Standards:
- **Strict Typing**: Use Luau type annotations wherever possible.
- **Priority**: If a module *must* initialize before others, define a `Priority` property (e.g., `DataService` uses `-70`).
- **Remotes**: Always use `RemoteRegistry` to get/define remotes. Do not manually create `RemoteEvent` or `RemoteFunction` instances in the Workspace.
