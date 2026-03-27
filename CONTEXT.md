# Project Architecture: CaptureBrainRots

This document provides a comprehensive architectural guide for developers and AI assistants working on `CaptureBrainRots`.

---

## 🏗️ Core Framework: ModuleLoader

The project uses a custom Service/Controller framework that manages the lifecycle and dependencies of all modules.

### Lifecycle Methods:
1. `Init(runtime)`: Called for all modules in order of `Priority` (lowest first). Used for state initialization, remote registration, and internal setup.
2. `Start(runtime)`: Called after ALL `Init` methods have completed. Used for cross-service logic and starting game loops.

### The `runtime` Object:
Passed to every `Init` and `Start` method, providing access to:
- `Config`: The merged and (on client) sanitized configuration.
- `Remotes`: The `RemoteRegistry` module for networking.
- `GetService(name)` (Server) / `GetController(name)` (Client): Access to other loaded modules.
- `Player` (Client only): The LocalPlayer.

### Priority:
Modules can define a `Priority` property (default 0). Lower numbers initialize and start earlier.
- `ConfigService`: Priority -1000 (Initializes first to provide configs).
- `DataService`: Priority -70.
- `BaseService`: Priority -50.
- `AnimalService`: Priority -40.

---

## 📡 Networking & Configuration

### Centralized Networking (`RemoteRegistry.luau`):
- All Remotes are lazily created by the Server and parented to `ReplicatedStorage/RuntimeRemotes`.
- The Client uses `WaitForChild` via the registry to ensure they exist.
- Adding a remote: Define its name in `ServerConfig.Remotes` and add a getter in `RemoteRegistry.luau`.

### Tiered Configuration:
1. `GameConfig (Shared)`: Common settings like the Remote Folder name.
2. `ServerConfig (Server)`: Sensitive data, balancing constants (Animal Stats, Spawn Pools, Admin IDs).
3. `ConfigService`: On Client startup, it fetches a **sanitized** subset of `ServerConfig` (Upgrades, Monetization, Weapons, Rarity Order) to be used for UI and local logic.

---

## 💾 Data Persistence (`DataService.luau`)

Handles recursive serialization of player state into DataStores.

### Serialization Capabilities:
- **Folders/ValueObjects**: Recursively saves attributes and values.
- **Inventory (`Backpack` & `Character`)**: Uses `AnimalService` to serialize tools into specialized table formats (`AnimalTool`, `TemplateTool`).
- **Base Snapshots**: Works with `BaseService` to save the state of player pads, including placed animals and accumulated cash.

---

## 🐾 Animal System (`AnimalService.luau`)

The core of the game loop. Animals are captured, stored in inventory, and placed on base pads.

### Key Stats & Calculations:
- **Rarity**: Common, Uncommon, Rare, Legendary, Mythical, Devine.
- **Leveling**: Stats scale exponentially based on a base value and level (using `Animals.Leveling` config).
- **Mutations**: 
    - `Gold`: 4x Revenue multiplier, specialized visual style (Glacier material, gold texture).
    - `Malevolent`: 10x Revenue multiplier, spawned during specialized events.
    - `Soaked`: 1.5x Revenue multiplier, applied during Rain events.
    - `Twistborn`: Applied during Tornado events.
    - `Alien`: Applied during Abduction events.

### Lifecycle:
- **Wild**: Spawned by `SpawnService` with random stats/level.
- **Captured**: Converted into a Tool in the player's backpack.
- **Placed**: Parented to a Base Pad via `AnimalService:RestorePlacedAnimal`.

---

## 🏠 Base & Tycoon System (`BaseService.luau`)

Manages player-owned bases and passive income.

- **Pads**: The primary income generators. When an animal is placed, it adds its `Revenue` to the pad's `StoredCash` every second.
- **Multipliers**: Base-wide revenue multipliers can be applied (e.g., from player stats).
- **Collection**: Players touch a "Collector" part to move `StoredCash` from the pad to their `leaderstats.Bucks`.
- **Stealing**: A unique mechanic where players can pay (via Developer Product) to "steal" an animal from another player's base. This is handled by `AnimalService` and `DataService`.

---

## 🌪️ Event System (`EventService.luau`)

The server periodically triggers events that modify the world and its inhabitants.

- **Rain**: Applies the `Soaked` mutation to wild and placed animals.
- **Tornado**: Spawns tornadoes that apply the `Twistborn` mutation.
- **Shrine**: Damages wild animals, making them easier to capture.
- **Abduction**: UFOs that abduct animals and apply the `Alien` mutation.

---

## ⚔️ Combat & Weapons (`WeaponService.luau`)

- **Tagging**: Weapons are identified by a specific CollectionService tag (defined in `Config.Weapons.Tag`).
- **Logic**: Handles hit detection, damage calculations (including upgrades), and playing effects/sounds.

---

## 🐣 Spawning & Areas (`SpawnService.luau`)

- **Spawn Areas**: Defined in `Workspace.SpawnAreas`. Each area has its own `SpawnPool` (defined in `ServerConfig.Animals.SpawnPools`).
- **Rarity Weights**: The service rolls for rarity based on weights, then selects a random animal template from that rarity folder in `ServerStorage`.
- **Floor Alignment**: Uses a sophisticated raycasting logic to ensure animals are perfectly aligned with the floor (even if they have complex collision boxes).

---

## 📈 Player Progression (`UpgradeService.luau`)

- **Walkspeed**: Players can upgrade their walkspeed using passive income. The service manages applying these upgrades on respawn.
- **Weapons**: Handles upgrading the damage and level of player tools.
- **Upgrade Shops**: Proximity-triggered shops that open a UI for player progression.

---

## 📁 Project Structure

- `src/Shared/ModuleLoader.luau`: Framework core.
- `src/Shared/Modules/RemoteRegistry.luau`: Networking hub.
- `src/Server/Services/`: Backend logic (Animal, Base, Data, Event, Weapon, etc.).
- `src/Client/Controllers/`: Frontend logic (UI, Effects, Input, Admin).
- `src/Shared/Config/`: Global game data.
- `src/Server/Config/`: Server-only constants.
- `src/Server/Main.server.luau`: Server entry point.
- `src/Client/Main.client.luau`: Client entry point.
