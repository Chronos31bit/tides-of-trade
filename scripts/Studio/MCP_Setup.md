# Roblox Studio MCP — Cursor setup

One-time setup so the Cursor agent can run Luau, generate assets, and inspect your open place.

## 1. Roblox Studio

1. Open your Tides of Trade place in **Roblox Studio** (latest version).
2. Open **Assistant** (top bar).
3. Click **…** → **Manage MCP Servers**.
4. Turn on **Enable Studio as MCP server**.
5. Optional: under **Quick connect**, enable **Cursor** (writes config for you).

When connected, you should see a **green indicator** with client count (e.g. `1`).

## 2. Cursor

MCP config lives in **one place only** (global):

`%USERPROFILE%\.cursor\mcp.json`

It points at:

`%LOCALAPPDATA%\Roblox\mcp.bat` → `StudioMCP.exe`

**After any config change:**

1. **Cursor Settings → MCP** — confirm `Roblox_Studio` is enabled and shows running (not error).
2. **Fully quit and reopen Cursor** (reload window is often not enough).
3. Open this workspace: `tides-of-trade`.
4. Start a **new Agent chat** and ask: *"Run execute_luau to return game.Name"*.

## 3. Verify

| Where | What to check |
|--------|----------------|
| Studio | Assistant → MCP Servers → green client count |
| Cursor | Settings → MCP → `Roblox_Studio` running |
| Agent | `execute_luau` returns your place name, not "No MCP servers available" |

## 4. Harbor assets (optional)

Once MCP works, follow [MCP_HarborBuildings.md](./MCP_HarborBuildings.md) to scaffold `ReplicatedStorage.Assets.Buildings` and generate tier visuals.

Rain placeholder: `ReplicatedStorage.Assets.Weather.Rain.RainEmitter` (ParticleEmitter; swap texture via `GameConfig.Weather.Rain.PlaceholderTextureId`).

Emote stubs: run [`CommandBar_SetupEmoteAnimations.luau`](./CommandBar_SetupEmoteAnimations.luau) to create `ReplicatedStorage.Assets.Animations` (wave, dance, fish_pose, salute, bow).

## Troubleshooting

### Cursor shows two `Roblox_Studio` entries

You had **both** global (`~/.cursor/mcp.json`) and project (`.cursor/mcp.json`) configs. This repo now uses **global only** — do not re-add `.cursor/mcp.json` unless you remove the global entry.

In **Settings → Tools & MCP**, delete or disable the duplicate, then restart Cursor.

### "No tools, prompts, or resources" (connected but empty)

Cursor logs show: `Timed out waiting for tools to become available`. The stdio bridge starts, but Studio did not register tools in time.

Try in order:

1. **Open your place first**, wait until Studio finishes loading, then enable MCP in Assistant.
2. **Reduce client count** — Studio showing "4 clients" often means duplicate Cursor connections + Claude. Turn off **Quick connect → Claude Desktop** if you only need Cursor. Use one Cursor MCP entry.
3. **Refresh the connection** — Cursor: toggle `Roblox_Studio` off → wait 5s → on. Or restart Cursor with Studio already open and MCP enabled.
4. **Verify tools loaded** — After refresh, the MCP row should list tools (`execute_luau`, `script_read`, …), not "No tools…".
5. **New Agent chat** after tools appear.

### Agent still says "No MCP servers available"

- Restart Cursor fully after fixing duplicates.
- Confirm **Settings → MCP** shows tools on the server row (not empty).
- Start a **new** Agent chat (old chats may not pick up MCP).

### Other

- **MCP server error in Cursor** — Confirm `C:\Users\derin\AppData\Local\Roblox\mcp.bat` exists (created when you enable MCP in Studio).
- **Multiple Studio windows** — Use MCP tool `list_roblox_studios` then `set_active_studio` to target the right place.
- **Docs** — [Connect to the Roblox Studio MCP server](https://create.roblox.com/docs/studio/mcp)
