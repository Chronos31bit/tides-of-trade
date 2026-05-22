# StarterGui assets (Rojo)

ScreenGui templates authored in Studio and synced into the game via Rojo.

## Sync path

Every `.rbxmx` or `.model.json` file in this folder becomes a **direct child** of:

`game.StarterGui.StarterGuiAssets`

at sync time (not a child of `ReplicatedStorage.TidesClient.UI` — that tree is Luau modules only).

## Naming

- Template ScreenGuis end with `_Template` (e.g. `HUD_Template.rbxmx` → instance `HUD_Template`).
- Runtime clones drop the suffix (e.g. `HUD`) when spawned into `PlayerGui`.

## Template defaults

- `Enabled = false` on every template so nothing flashes in Studio or before a controller clones it.
- Layout is **data, not code**: use `UIListLayout`, `UIGridLayout`, `UIPadding`, `UICorner`, `UIStroke`, `UIScale`, `UISizeConstraint`, `UIAspectRatioConstraint`, etc. Controllers wire behavior (labels, `Activated`, visibility, tweens) — they should not build layout with `Instance.new`.

## Authoring workflow

1. Build or edit the ScreenGui under `StarterGui → StarterGuiAssets` in Studio.
2. Right-click the instance → **Save to File…** → save into this folder as `Name_Template.rbxmx`.
3. Commit the `.rbxmx`; Rojo sync round-trips on the next connect.

Tunable numbers (colors, spacing, font sizes, modal widths) stay in `GameConfig.UI`. Templates use sensible defaults; controllers may override at runtime from config.

## ModalShell

- **Rojo source:** `ModalShell_Template.model.json` (hand-authored, syncs on connect).
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildModalShellTemplate.luau` in the command bar, then optionally **Save to File…** as `ModalShell_Template.rbxmx` for artist round-trips.
- **Runtime:** `UIKit.ModalShell` clones via `TemplateLoader.spawn("ModalShell", { instanceName = opts.name })`.

## HUD

- **Rojo source:** `HUD_Template.model.json` (hand-authored, syncs on connect). Optional Studio export: `HUD_Template.rbxmx`.
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildHUDTemplate.luau` in the command bar, then **Save to File…** as `HUD_Template.rbxmx` if artists prefer rbxmx round-trips.
- **Runtime:** `HUD.create()` clones via `TemplateLoader.spawn("HUD")`, resolves named refs, and applies `UIKit.skinActionButton` on action-bar tiles.
- **Meta:** `DisplayOrderKey = "HUD"`, `ResetOnSpawn = false`, `RespectTopbar = true`.
