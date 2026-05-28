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

### Previewing HUD layout without Play Solo

The **live** HUD (`PlayerGui.HUD`) is only created when you **Play Solo** — `HUDController` runs `HUD.create()` on `KnitStart`.

In **Edit mode**, you can still eyeball the layout:

1. Rojo-sync so `StarterGui → StarterGuiAssets → HUD_Template` exists.
2. Select `HUD_Template` in Explorer and temporarily set **Enabled = true** (template stays in `StarterGuiAssets`; it does not use the runtime clone path).
3. Set **Enabled** back to **false** before play-testing so you do not rely on a visible template copy.

There is no always-on Edit-mode HUD clone by design — templates must stay disabled so they are not duplicated alongside `TemplateLoader.spawn("HUD")`.
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

- **Canonical Rojo source:** `HUD_Template.model.json` only (do not commit a parallel `HUD_Template.rbxmx` unless you replace the `.model.json` and drop the duplicate).
- **Optional Studio export:** after visual edits, **Save to File…** as `HUD_Template.rbxmx` for artist round-trips — re-import or hand-merge back into `.model.json` before commit.
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildHUDTemplate.luau` in the command bar (regenerates layout including Harbor **BUILD** tile glyph `🔨`).
- **Runtime:** `HUD.create()` clones via `TemplateLoader.spawn("HUD")`, resolves named refs, and applies `UIKit.skinActionButton` on action-bar tiles.
- **Meta:** `DisplayOrderKey = "HUD"`, `ResetOnSpawn = false`, `RespectTopbar = true`.

## Inventory

- **Canonical Rojo source:** `InventoryUI_Template.model.json`.
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildInventoryUITemplate.luau` in the command bar (adds `TotInvFilterChip` tags on filter chips).
- **Runtime:** `InventoryUI.show()` clones via `TemplateLoader.spawn("Inventory", { instanceName = "InventoryUI" })`; fish thumbnails use `UIKit.attachFishThumb`.
- **Meta:** `DisplayOrderKey = "Modal"`, `ResetOnSpawn = false`, `IgnoreGuiInset = true`, `FadeDuration` / `SlideOffsetPx` for open tween.

## Market

- **Canonical Rojo source:** `MarketUI_Template.model.json`.
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildMarketUITemplate.luau` in the command bar.
- **Runtime:** `MarketUI.show()` clones via `TemplateLoader.spawn("Market", { instanceName = "MarketUI" })`; listing thumbs use `UIKit.attachFishThumb`; buy uses slide-in `BuyConfirm` tween on the row.
- **Meta:** `DisplayOrderKey = "Modal"`, `ResetOnSpawn = false`, `IgnoreGuiInset = true`.

## Quest tracker

- **Canonical Rojo source:** `QuestTrackerUI_Template.model.json`.
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildQuestTrackerUITemplate.luau` in the command bar.
- **Runtime:** `QuestTrackerUI.create()` clones via `TemplateLoader.spawn("QuestTracker", { instanceName = "QuestTrackerUI" })`; quest rows clone `QuestRow_Template`.
- **Meta:** `DisplayOrderKey = "QuestTracker"`, `RespectTopbar = true`, `ClaimTweenDuration` / `ClaimTweenEasingStyle` / `ClaimTweenEasingDirection` / `PopupSlideOffsetPx` / `PopupRestOffsetX` for completion popup slide tweens.

## Aquarium

- **Canonical Rojo source:** `AquariumUI_Template.model.json`.
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildAquariumUITemplate.luau` in the command bar.
- **Runtime:** `AquariumUI.show()` clones via `TemplateLoader.spawn("Aquarium", { instanceName = "AquariumUI" })`; **3-column** grid (`Meta.SlotGridColumns`, default 152×180 px cells); each filled slot shows species name, `+X coins/s · weight kg` (weight + modifiers in `Shared.Util.AquariumIncome`), and up to three modifier pills. Inventory **Sort** cycles: default → best → worst by coins/s.
- **Meta:** `DisplayOrderKey = "Modal"`, `ResetOnSpawn = false`, `IgnoreGuiInset = true`, `MaxAquariumCapacity = 24`, `SlotGridColumns = 4`, `FadeDuration` / `SlideOffsetPx` for open tween.

## Harbor edit (build mode)

- **Canonical Rojo source:** `HarborEditUI_Template.model.json`.
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildHarborEditUITemplate.luau` in the command bar.
- **Runtime:** `HarborEditUI.show()` clones via `TemplateLoader.spawn("HarborEdit", { instanceName = "HarborEditUI" })`; palette rows clone `BuildingRow_Template` per `BuildingCatalog` entry (costs from `GameConfig.Buildings`); building thumbs use `UIKit.attachBuildingThumb`; global **Upgrade** uses `UIKit.skinUpgradeButton`.
- **Meta:** `DisplayOrderKey = "Modal"`, `ResetOnSpawn = false`, `RespectTopbar = true`.

## Smokehouse

- **Canonical Rojo source:** `SmokehouseUI_Template.model.json`.
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildSmokehouseUITemplate.luau` in the command bar.
- **Runtime:** `SmokehouseUI.show()` clones via `TemplateLoader.spawn("Smokehouse", { instanceName = "SmokehouseUI" })`; smoke slots pre-pooled to `Meta.MaxSmokehouseSlots`; inventory rows clone `InvFishRow_Template`; **Collect All** claims every ready slot (server claim → quest progress unchanged).
- **Meta:** `DisplayOrderKey = "Modal"`, `ResetOnSpawn = false`, `IgnoreGuiInset = true`, `MaxSmokehouseSlots = 10`, `FadeDuration` / `SlideOffsetPx`.

## Dialogue (NPC)

- **Canonical Rojo source:** `DialogueUI_Template.model.json`.
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildDialogueUITemplate.luau` in the command bar.
- **Runtime:** `DialogueUI.create()` clones via `TemplateLoader.spawn("Dialogue", { instanceName = "TutorialDialogue" })`; text-only (no TTS); typewriter + panel slide in script; `ChoiceButton_Template` reserved for future branching.
- **Meta:** `DisplayOrderKey = "Dialogue"`, `ResetOnSpawn = false`, `RespectTopbar = true`. Not a modal — world keeps moving.

## Notification (toasts)

- **Canonical Rojo source:** `NotificationUI_Template.model.json`.
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildNotificationUITemplate.luau` in the command bar.
- **Runtime:** `NotificationUI.create()` clones via `TemplateLoader.spawn("Notification", { instanceName = "NotificationUI" })`; toasts clone `Toast_Template` into `StackContainer` (FIFO cap from `GameConfig.UI.Notification`).
- **Meta:** `DisplayOrderKey = "Notification"`, `RespectTopbar = true`. Fade in/out only (no slide), including under Reduced Motion.

## Rod select

- **Canonical Rojo source:** `RodSelectUI_Template.model.json`.
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildRodSelectUITemplate.luau` in the command bar.
- **Runtime:** `RodSelectUI.show()` clones via `TemplateLoader.spawn("RodSelect", { instanceName = "RodSelectUI" })`; rows clone `RodRow_Template` (`TierBadge`, `NameLabel`, `EffectSummaryLabel`, `EquipButton`, `LockOverlay`).
- **Meta:** `DisplayOrderKey = "Modal"`, `IgnoreGuiInset = true`. `RodSelectController` → `RodService:EquipRod` unchanged.

## Social

- **Canonical Rojo source:** `SocialUI_Template.model.json`.
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildSocialUITemplate.luau` in the command bar.
- **Runtime:** `SocialUI.show()` clones via `TemplateLoader.spawn("Social", { instanceName = "SocialUI" })`; emotes wired in script; `Tabs` / `PlayerRow_Template` / hidden `ChatPanel` reserved for Crew v1.
- **Meta:** `DisplayOrderKey = "Modal"`, `IgnoreGuiInset = true`. `SocialController` → `SocialService:PlayEmote` unchanged.

## Shop

- **Canonical Rojo source:** `ShopUI_Template.model.json`.
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildShopUITemplate.luau` in the command bar.
- **Runtime:** `ShopUI.show()` clones via `TemplateLoader.spawn("Shop", { instanceName = "ShopUI" })`; rows clone `ShopRow_Template` (`NameLabel`, `DescriptionLabel`, `PriceLabel`, `BuyButton`).
- **Meta:** `DisplayOrderKey = "Modal"`, `ThemeKey = "modal-teal"`. Colors applied at spawn via `UIKit.applySpawnedChrome` / `applyCardStyle`.

## Admin weather

- **Canonical Rojo source:** `AdminWeatherUI_Template.model.json`.
- **Studio rebuild:** run `scripts/Studio/CommandBar_BuildAdminWeatherUITemplate.luau` in the command bar.
- **Runtime:** `AdminWeatherUI.build()` clones via `TemplateLoader.spawn("AdminWeather")`; weather rows clone `WeatherButton_Template`; dev row clones `DevToggle_Template` (auto Markov). **Only** `AdminController` after `AdminService:IsAdmin()`.
- **Meta:** `DisplayOrderKey = "Admin"` (70), `ThemeKey = "admin"`.

## Template lint (Studio)

- **Module:** `ServerScriptService.Tools.ValidateStarterGui`
- **Run:** `require(game.ServerScriptService.Tools.ValidateStarterGui).run()` in the command bar after Rojo sync.
- Checks: `Meta.DisplayOrderKey`, `ResetOnSpawn=false`, 44px buttons, 12px fonts, `TextScaled=false`, `Selectable` on interactives.
- All `*_Template.model.json` files include `Meta.ThemeKey` + `Selectable` on buttons (batch pass May 2026).
