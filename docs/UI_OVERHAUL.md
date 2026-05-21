# UI Design System — Tides of Trade

This document is the reference for the client UI design system. Everything
below is enforced by `src/Client/UI/UIUtil.lua` (helpers) and tuned via
`src/Shared/Config/GameConfig.lua` (`GameConfig.UI.*`).

If you're touching a feature UI file, the rules:

1. **Never call `Color3.fromRGB(...)` in `src/Client/UI/*` outside `UIUtil.lua`.**
   Use `UIUtil.Palette.<Name>`, `UIUtil.rarityColor`, or `UIUtil.modifierColor`.
2. **Never call `TweenService:Create` in a feature UI module.** Use
   `MotionUtil.tween` (always animates) or `MotionUtil.tweenOrSnap` (snaps
   under `GuiService.ReducedMotionEnabled`).
3. **Every `TextLabel` is ≥ 12px (`UIUtil.MinFontPx`).** `UIUtil.makeLabel`
   warns in Studio if you go below.
4. **Every interactive `TextButton` is ≥ 44px tall (`UIUtil.MinTouchPx`).**
   `UIUtil.makePrimaryButton` etc. enforce this in Studio.
5. **Modal chrome comes from `UIUtil.makeModalShell`.** Do not hand-roll
   backdrop / panel / header / close button.

## Palette names

Use these by name from `UIUtil.Palette`:

| Group     | Names                                                                  |
| --------- | ---------------------------------------------------------------------- |
| Sunset    | `Sunset`, `SunsetDeep`, `SunsetSoft`                                   |
| Sea       | `Teal`, `TealDark`, `TealDeeper`, `TealLight`                          |
| Wood      | `Wood`, `WoodDark`, `WoodLight`                                        |
| Text      | `Cream`, `CreamSoft`, `Ink`                                            |
| Currency  | `Gold`, `GoldDeep`, `Lure`                                             |
| Rarity    | `Common`, `Uncommon`, `Rare`, `Epic`, `Legendary`, `Mythic`, `Divine`  |
| Feedback  | `Danger`, `Success`                                                    |
| Chrome    | `Shadow`, `ThumbLight`                                                 |

Two lookup tables live alongside the named entries:

- `UIUtil.Palette.Rarity[name]` — map form for dynamic lookups.
- `UIUtil.Palette.Modifiers[modifierId]` — built from
  `GameConfig.ModifierGlow` at module load; ensures inventory pills and
  glow rings never drift apart.

Helpers:

- `UIUtil.rarityColor(rarity)` — falls back to `Common` for unknown values.
- `UIUtil.modifierColor(id)` — falls back to `CreamSoft` for unknown ids.

## DisplayOrder map

Every `ScreenGui` in `src/Client/UI/*` sets `gui.DisplayOrder =
UIUtil.DisplayOrder.<role>`. Higher = drawn on top.

| Role           | Value | Used by                                                            |
| -------------- | ----: | ------------------------------------------------------------------ |
| `World`        |     0 | world-anchored BillboardGuis (waypoints, ProximityPrompts)         |
| `HUD`          |    10 | bottom action bar, currency wallet, rod chip                       |
| `QuestTracker` |    12 | right-edge tracker tab + completion / streak popups                |
| `Dialogue`     |    20 | Mira NPC chat box                                                  |
| `CastMeter`    |    30 | fishing overlay (above HUD, below modals)                          |
| `Modal`        |    40 | Inventory / Market / Harbor / Rod / Bait / Aquarium / Shop / Social |
| `CatchReveal`  |    50 | catch celebration card (above all modals)                          |
| `Tutorial`     |    60 | tutorial highlight overlay (sits above everything)                 |

Source of truth: `GameConfig.UI.DisplayOrder` in
`src/Shared/Config/GameConfig.lua`.

## Spacing, radii, typography

Re-exported from `GameConfig.UI` so designers can tune values in one place
and feature code reads them by name:

```lua
UIUtil.Spacing   -- { xs=4, sm=8, md=12, lg=16, xl=24, xxl=32 }
UIUtil.Radii     -- { sm=6, md=10, lg=12, xl=16, pill=999 }
UIUtil.Typography
-- { display = { font, size=28 },
--   title    = { font, size=20 },
--   subtitle = { font, size=16 },
--   body     = { font, size=15 },
--   caption  = { font, size=12 } } -- 12 is the FLOOR
```

`UIUtil.makeLabel(text, style, props)` reads the matching token and floors
size at `MinFontPx` (12).

## How to add a new modal

```lua
local UIUtil = require(script.Parent.UIUtil)

local MyModal = {}

function MyModal.show(data, onConfirm, onClose)
    local shell
    shell = UIUtil.makeModalShell({
        name = "MyModal",          -- ScreenGui name (auto-dedupes)
        title = "My Modal",
        onClose = function()
            if shell then shell.destroy() end
            if onClose then onClose() end
        end,
        width = 440,               -- optional, default Modal.MaxWidthPx
        heightScale = 0.78,        -- optional, default 0.78
    })

    -- Mount your content into `shell.body`. The body already has 16px
    -- padding and sits below the 56px header.
    local body = shell.body

    local confirm = UIUtil.makePrimaryButton("Confirm", function()
        shell.destroy()
        onConfirm()
    end, {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, 0, 1, 0),
        Size = UDim2.fromOffset(140, UIUtil.MinTouchPx),
    })
    confirm.Parent = body

    return {
        gui = shell.gui,
        close = function() shell.destroy() end,
    }
end

return MyModal
```

The shell handles the dark backdrop, max-width clamp (UISizeConstraint),
rounded panel, header bar with title + close button, slide/fade animation
(or snap under ReducedMotion), and tap-outside-to-dismiss.

## ReducedMotion conventions

`GuiService.ReducedMotionEnabled` is a Roblox accessibility setting.
`MotionUtil.reducedMotionEnabled()` is the cached read; it updates on the
GuiService property-changed signal.

| Decorative motion             | ReducedMotion behaviour                |
| ----------------------------- | -------------------------------------- |
| Modal slide-up + fade-in      | Snap to final position; fade only     |
| Catch-reveal slide / orbit    | Static angle, no orbit, no sparkles    |
| Camera shake on cast splash   | Skipped                                |
| Pill stagger fade-in          | All pills appear together              |
| Animated stroke colour cycle  | Stroke stays at base rarity colour     |

**Never disable gameplay motion** — only decoration. The cast meter still
oscillates, the XP bar still fills, the reel zone still moves.

Use:
- `MotionUtil.tween(inst, info, props)` when you want the animation to run
  regardless (and you've already gated on `reducedMotionEnabled()`).
- `MotionUtil.tweenOrSnap(inst, info, props)` for hover/press/transitions
  that should auto-snap under the setting.

## Touch + font floors

- **44px minimum interactive height.** `UIUtil.MinTouchPx`. Enforced by
  `makePrimaryButton`/`makeSecondaryButton`/`makeGhostButton`/`makeDangerButton`.
  The Modal close button is exactly 44px (`Modal.CloseButtonPx`).
- **12px minimum effective text size.** `UIUtil.MinFontPx`. Enforced by
  `makeLabel`. If you must override `TextSize` on a label, keep it ≥ 12.

## Justified exceptions (audit allow-list)

The grep audit (`Color3.fromRGB` in `src/Client/UI/` outside `UIUtil.lua`)
should report zero hits. If a new exception is justified (e.g. a viewport
lighting tint that isn't a chrome colour), document it here with a one-line
reason before merging.

- *(currently empty — no exceptions)*

## File map

- Tokens: `src/Shared/Config/GameConfig.lua` → `GameConfig.UI.*`
- Helpers: `src/Client/UI/UIUtil.lua`
- Motion: `src/Shared/Util/MotionUtil.lua`
- Modal screens: `src/Client/UI/{InventoryUI,MarketUI,HarborEditUI,RodSelectUI,BaitShopUI,AquariumUI,ShopUI,SocialUI}.lua`
- Overlays: `src/Client/UI/{HUD,CastMeter,CatchRevealUI,QuestTrackerUI,DialogueUI}.lua`
