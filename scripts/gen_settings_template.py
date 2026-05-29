"""One-off generator for SettingsUI_Template.model.json."""
import json
from pathlib import Path


def rgb(r: int, g: int, b: int) -> list[float]:
    return [r / 255, g / 255, b / 255]


def udim2(xs: float, xo: int, ys: float, yo: int) -> dict:
    return {"UDim2": [[xs, xo], [ys, yo]]}


def udim(o: int) -> dict:
    return {"UDim": [0, o]}


def corner(r: int) -> dict:
    return {
        "Name": "UICorner",
        "ClassName": "UICorner",
        "Properties": {"CornerRadius": udim(r)},
    }


def stroke() -> dict:
    return {
        "Name": "UIStroke",
        "ClassName": "UIStroke",
        "Properties": {
            "Color": rgb(172, 152, 122),
            "Thickness": 1.2,
            "Transparency": 0.25,
            "ApplyStrokeMode": "Border",
        },
    }


def textbtn(name: str, text: str, layout: int) -> dict:
    return {
        "Name": name,
        "ClassName": "TextButton",
        "Properties": {
            "Text": text,
            "AutoButtonColor": False,
            "BorderSizePixel": 0,
            "BackgroundColor3": rgb(245, 236, 218),
            "Font": "Gotham",
            "TextSize": 12,
            "TextColor3": rgb(96, 80, 64),
            "TextWrapped": True,
            "Size": udim2(0.33, -8, 1, 0),
            "LayoutOrder": layout,
            "Selectable": True,
        },
        "Children": [corner(10), stroke()],
    }


def section(name: str, title: str, order: int, body_name: str, body_children: list) -> dict:
    return {
        "Name": name,
        "ClassName": "Frame",
        "Properties": {
            "BackgroundColor3": rgb(232, 220, 198),
            "BorderSizePixel": 0,
            "AutomaticSize": "Y",
            "Size": udim2(1, 0, 0, 0),
            "LayoutOrder": order,
        },
        "Children": [
            corner(10),
            stroke(),
            {
                "Name": "UIPadding",
                "ClassName": "UIPadding",
                "Properties": {
                    "PaddingTop": udim(12),
                    "PaddingBottom": udim(12),
                    "PaddingLeft": udim(12),
                    "PaddingRight": udim(12),
                },
            },
            {
                "Name": "UIListLayout",
                "ClassName": "UIListLayout",
                "Properties": {
                    "FillDirection": "Vertical",
                    "SortOrder": "LayoutOrder",
                    "Padding": udim(8),
                },
            },
            {
                "Name": "SectionTitle",
                "ClassName": "TextLabel",
                "Properties": {
                    "BackgroundTransparency": 1,
                    "Text": title,
                    # Rojo's rbx-dom Enum.Font DB has no GothamSemibold; the
                    # project-wide convention uses GothamBold for headings.
                    # Runtime GameConfig.UI.Typography.subtitle still uses
                    # Enum.Font.GothamSemibold (valid in-engine).
                    "Font": "GothamBold",
                    "TextSize": 16,
                    "TextColor3": rgb(48, 38, 28),
                    "TextXAlignment": "Left",
                    "AutomaticSize": "Y",
                    "Size": udim2(1, 0, 0, 0),
                    "LayoutOrder": 0,
                },
            },
            {
                "Name": body_name,
                "ClassName": "Frame",
                "Properties": {
                    "BackgroundTransparency": 1,
                    "BorderSizePixel": 0,
                    "AutomaticSize": "Y",
                    "Size": udim2(1, 0, 0, 0),
                    "LayoutOrder": 1,
                },
                "Children": [
                    {
                        "Name": "UIListLayout",
                        "ClassName": "UIListLayout",
                        "Properties": {
                            "FillDirection": "Vertical",
                            "SortOrder": "LayoutOrder",
                            "Padding": udim(8),
                        },
                    },
                    *body_children,
                ],
            },
        ],
    }


hint = (
    "Reduce on-screen animation. Auto follows your device's accessibility setting."
)

audio = section(
    "AudioSection",
    "Audio",
    1,
    "AudioBody",
    [
        {
            "Name": "VolumeLabel",
            "ClassName": "TextLabel",
            "Properties": {
                "BackgroundTransparency": 1,
                "Text": "Master volume",
                "Font": "GothamMedium",
                "TextSize": 15,
                "TextColor3": rgb(48, 38, 28),
                "TextXAlignment": "Left",
                "AutomaticSize": "Y",
                "Size": udim2(1, 0, 0, 0),
                "LayoutOrder": 0,
            },
        },
        {
            "Name": "VolumeSliderMount",
            "ClassName": "Frame",
            "Properties": {
                "BackgroundTransparency": 1,
                "BorderSizePixel": 0,
                "Size": udim2(1, 0, 0, 44),
                "LayoutOrder": 1,
            },
        },
        {
            "Name": "MuteToggleMount",
            "ClassName": "Frame",
            "Properties": {
                "BackgroundTransparency": 1,
                "BorderSizePixel": 0,
                "Size": udim2(1, 0, 0, 44),
                "LayoutOrder": 2,
            },
        },
    ],
)

motion = section(
    "MotionSection",
    "Motion",
    2,
    "MotionBody",
    [
        {
            "Name": "MotionHint",
            "ClassName": "TextLabel",
            "Properties": {
                "BackgroundTransparency": 1,
                "Text": hint,
                "Font": "Gotham",
                "TextSize": 12,
                "TextColor3": rgb(96, 80, 64),
                "TextWrapped": True,
                "TextXAlignment": "Left",
                "AutomaticSize": "Y",
                "Size": udim2(1, 0, 0, 0),
                "LayoutOrder": 0,
            },
        },
        {
            "Name": "ModeRow",
            "ClassName": "Frame",
            "Properties": {
                "BackgroundTransparency": 1,
                "BorderSizePixel": 0,
                "Size": udim2(1, 0, 0, 44),
                "LayoutOrder": 1,
            },
            "Children": [
                {
                    "Name": "UIListLayout",
                    "ClassName": "UIListLayout",
                    "Properties": {
                        "FillDirection": "Horizontal",
                        "SortOrder": "LayoutOrder",
                        "Padding": udim(8),
                    },
                },
                textbtn("Mode_auto", "Auto", 1),
                textbtn("Mode_off", "Always Off", 2),
                textbtn("Mode_reduced", "Always Reduced", 3),
            ],
        },
    ],
)

credits = section("CreditsSection", "Credits", 3, "CreditsBody", [])

model = {
    "ClassName": "ScreenGui",
    "Properties": {
        "Enabled": False,
        "ResetOnSpawn": False,
        "IgnoreGuiInset": True,
        "ZIndexBehavior": "Sibling",
    },
    "Children": [
        {
            "Name": "Meta",
            "ClassName": "Folder",
            "Children": [
                {
                    "Name": "DisplayOrderKey",
                    "ClassName": "StringValue",
                    "Properties": {"Value": "Modal"},
                },
                {
                    "Name": "ResetOnSpawn",
                    "ClassName": "BoolValue",
                    "Properties": {"Value": False},
                },
                {
                    "Name": "IgnoreGuiInset",
                    "ClassName": "BoolValue",
                    "Properties": {"Value": True},
                },
                {
                    "Name": "FadeDuration",
                    "ClassName": "NumberValue",
                    "Properties": {"Value": 0.18},
                },
                {
                    "Name": "SlideOffsetPx",
                    "ClassName": "NumberValue",
                    "Properties": {"Value": 24},
                },
                {
                    "Name": "ThemeKey",
                    "ClassName": "StringValue",
                    "Properties": {"Value": "modal-parchment"},
                },
            ],
        },
        {
            "Name": "Backdrop",
            "ClassName": "TextButton",
            "Properties": {
                "Text": "",
                "AutoButtonColor": False,
                "BackgroundColor3": [0, 0, 0],
                "BackgroundTransparency": 1,
                "BorderSizePixel": 0,
                "Size": udim2(1, 0, 1, 0),
                "ZIndex": 1,
                "Selectable": True,
            },
        },
        {
            "Name": "Panel",
            "ClassName": "Frame",
            "Properties": {
                "BackgroundColor3": rgb(245, 236, 218),
                "BorderSizePixel": 0,
                "AnchorPoint": [1, 1],
                "Position": udim2(1, -16, 1, -16),
                "Size": udim2(0, 360, 0, 520),
                "ZIndex": 2,
            },
            "Children": [
                corner(12),
                stroke(),
                {
                    "Name": "UISizeConstraint",
                    "ClassName": "UISizeConstraint",
                    "Properties": {"MaxSize": [440, 520]},
                },
                {
                    "Name": "Header",
                    "ClassName": "Frame",
                    "Properties": {
                        "BackgroundColor3": rgb(232, 220, 198),
                        "BorderSizePixel": 0,
                        "Size": udim2(1, 0, 0, 56),
                        "ZIndex": 3,
                    },
                    "Children": [
                        corner(12),
                        {
                            "Name": "HeaderMask",
                            "ClassName": "Frame",
                            "Properties": {
                                "BackgroundColor3": rgb(232, 220, 198),
                                "BorderSizePixel": 0,
                                "AnchorPoint": [0, 1],
                                "Position": udim2(0, 0, 1, 0),
                                "Size": udim2(1, 0, 0, 12),
                                "ZIndex": 3,
                            },
                        },
                        {
                            "Name": "HeaderDivider",
                            "ClassName": "Frame",
                            "Properties": {
                                "BackgroundColor3": rgb(210, 194, 168),
                                "BorderSizePixel": 0,
                                "AnchorPoint": [0, 1],
                                "Position": udim2(0, 0, 1, 0),
                                "Size": udim2(1, 0, 0, 1),
                                "ZIndex": 4,
                            },
                        },
                        {
                            "Name": "Title",
                            "ClassName": "TextLabel",
                            "Properties": {
                                "BackgroundTransparency": 1,
                                "Text": "Settings",
                                "Font": "GothamBold",
                                "TextSize": 20,
                                "TextColor3": rgb(48, 38, 28),
                                "TextXAlignment": "Left",
                                "TextYAlignment": "Center",
                                "Position": udim2(0, 16, 0, 0),
                                "Size": udim2(1, -76, 1, 0),
                                "ZIndex": 4,
                            },
                        },
                        {
                            "Name": "Close",
                            "ClassName": "TextButton",
                            "Properties": {
                                "AutoButtonColor": False,
                                "BorderSizePixel": 0,
                                "BackgroundColor3": rgb(232, 220, 198),
                                "Text": "X",
                                "Font": "GothamBold",
                                "TextColor3": rgb(96, 80, 64),
                                "TextScaled": False,
                                "TextSize": 20,
                                "AnchorPoint": [1, 0.5],
                                "Position": udim2(1, -12, 0.5, 0),
                                "Size": udim2(0, 44, 0, 44),
                                "ZIndex": 4,
                                "Selectable": True,
                            },
                            "Children": [corner(6)],
                        },
                    ],
                },
                {
                    "Name": "Body",
                    "ClassName": "Frame",
                    "Properties": {
                        "BackgroundTransparency": 1,
                        "BorderSizePixel": 0,
                        "Position": udim2(0, 0, 0, 56),
                        "Size": udim2(1, 0, 1, -56),
                        "ZIndex": 2,
                    },
                    "Children": [
                        {
                            "Name": "UIPadding",
                            "ClassName": "UIPadding",
                            "Properties": {
                                "PaddingLeft": udim(16),
                                "PaddingRight": udim(16),
                                "PaddingTop": udim(16),
                                "PaddingBottom": udim(16),
                            },
                        },
                        {
                            "Name": "Sections",
                            "ClassName": "ScrollingFrame",
                            "Properties": {
                                "BackgroundTransparency": 1,
                                "BorderSizePixel": 0,
                                "Size": udim2(1, 0, 1, 0),
                                "CanvasSize": udim2(0, 0, 0, 0),
                                "AutomaticCanvasSize": "Y",
                                "ScrollBarThickness": 6,
                                "ScrollBarImageColor3": rgb(172, 152, 122),
                                "ScrollingDirection": "Y",
                            },
                            "Children": [
                                {
                                    "Name": "UIListLayout",
                                    "ClassName": "UIListLayout",
                                    "Properties": {
                                        "FillDirection": "Vertical",
                                        "SortOrder": "LayoutOrder",
                                        "Padding": udim(12),
                                    },
                                },
                                {
                                    "Name": "UIPadding",
                                    "ClassName": "UIPadding",
                                    "Properties": {"PaddingRight": udim(8)},
                                },
                                audio,
                                motion,
                                credits,
                            ],
                        },
                    ],
                },
            ],
        },
    ],
}

out = Path(__file__).resolve().parents[1] / "src" / "StarterGuiAssets" / "SettingsUI_Template.model.json"
out.write_text(json.dumps(model, indent=2), encoding="utf-8")
print("wrote", out)
