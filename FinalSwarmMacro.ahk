#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 2

; Reduce interpreter/debug bookkeeping during long farming sessions.
ListLines False

CoordMode "Mouse", "Screen"
CoordMode "Pixel", "Screen"

SendMode "Event"
SetMouseDelay 10

; Keep the keyboard hook installed so the close key remains responsive.
InstallKeybdHook()

; ============================================================
; DISPLAY REQUIREMENTS
; Requires 1920x1080 resolution and 100% Windows display scale.
; 96 DPI = 100% scaling.
; ============================================================

scalePercent := Round(A_ScreenDPI / 96 * 100)

supportedResolution := (
    (A_ScreenWidth = 1920 && A_ScreenHeight = 1080)
    || (A_ScreenWidth = 1280 && A_ScreenHeight = 720)
)

if !supportedResolution || A_ScreenDPI != 96 {
    MsgBox(
        "This script requires one of these Windows display settings:`n`n"
        . "Resolution: 1920x1080 OR 1280x720`n"
        . "Scale: 100%`n`n"
        . "Detected resolution: " A_ScreenWidth "x" A_ScreenHeight "`n"
        . "Detected scale: " scalePercent "%`n`n"
        . "Open Windows Settings > System > Display, change the resolution to either 1920x1080 or 1280x720 and Scale to 100%, then run the script again.",
        "Unsupported Display Settings",
        "Icon!"
    )
    ExitApp
}

; ============================================================
; RESOLUTION SCALING
; All coordinates/images were originally made for 1920x1080.
; ============================================================

baseWidth := 1920
baseHeight := 1080

ScaleX(x) {
    global baseWidth
    return Round(x * A_ScreenWidth / baseWidth)
}

ScaleY(y) {
    global baseHeight
    return Round(y * A_ScreenHeight / baseHeight)
}

; GUI controls do not automatically shrink just because the screen
; resolution is lower, so scale their pixel sizes separately.
guiScale := (A_ScreenWidth = 1280 && A_ScreenHeight = 720) ? (2 / 3) : 1

GS(value) {
    global guiScale
    return Max(1, Round(value * guiScale))
}

; The updated game no longer always renders this pixel as pure FFFFFF.
; Treat only these four known values as the white/choice-ready state.
IsChoiceWhiteColor(color) {

    color := color & 0xFFFFFF

    return (
        color = 0xFCFCFC
        || color = 0xFDFDFD
        || color = 0xFEFEFE
        || color = 0xFFFFFF
    )
}

; Explicit white-detection point for each supported resolution.
if A_ScreenWidth = 1280 && A_ScreenHeight = 720 {
    whiteDetectX := 640
    whiteDetectY := 200
}
else {
    whiteDetectX := 960
    whiteDetectY := 300
}

; While waiting for white, keep the mouse 100 pixels above
; the actual white-detection point.
whiteRestX := whiteDetectX
whiteRestY := whiteDetectY - 100

SetSearchAreaForChoiceCount(choiceCount := 5) {

    global searchLeft
    global searchTop
    global searchRight
    global searchBottom

    switch choiceCount {

        case 1:
            searchLeft := ScaleX(880)
            searchTop := ScaleY(430)
            searchRight := ScaleX(1040)
            searchBottom := ScaleY(590)

        case 2:
            searchLeft := ScaleX(710)
            searchTop := ScaleY(430)
            searchRight := ScaleX(1210)
            searchBottom := ScaleY(590)

        case 3:
            searchLeft := ScaleX(530)
            searchTop := ScaleY(430)
            searchRight := ScaleX(1380)
            searchBottom := ScaleY(590)

        case 4:
            searchLeft := ScaleX(370)
            searchTop := ScaleY(430)
            searchRight := ScaleX(1550)
            searchBottom := ScaleY(590)

        default:
            ; Updated measured 5-choice rectangle.
            searchLeft := ScaleX(210)
            searchTop := ScaleY(430)
            searchRight := ScaleX(1710)
            searchBottom := ScaleY(590)
    }
}

RefreshScaledSearchArea() {
    ; Before a choice count is known, use the widest 5-choice range.
    SetSearchAreaForChoiceCount(5)
}


; ============================================================
; GUI POSITION
; ============================================================

; Use dedicated GUI positions for each supported resolution.
; This prevents the fixed-size GUIs from hanging off the right edge.

; Positions are based on the 1080p layout and scaled to the
; selected supported resolution.
guiX := ScaleX(1700)
guiY := ScaleY(40)

; The choice window supports 1 through 5 visible slots.
; Anchor it directly against the top-right edge.
choiceGuiWidthBase := 400
choiceGuiX := A_ScreenWidth - GS(choiceGuiWidthBase)
choiceGuiY := 0

farmingStarted := false
restartInProgress := false
autoClicking := false
farmPaused := false
resumeToWhiteRequested := false
pauseHotkeyWasDown := false

selectedIsland := ""
selectedChallenge := ""
selectedDifficulty := ""

priorityGui := 0
choiceGui := 0
pauseGui := 0
calibrationGui := 0
settingsGui := 0
keybindCaptureGui := 0

pauseToleranceDropdown := 0

settingsHotkeyValueText := 0
settingsPendingHotkey := ""
settingsPauseHotkeyValueText := 0
settingsPendingPauseHotkey := ""
settingsDarkModeCheckbox := 0
settingsStatusText := 0
keybindCaptureStatusText := 0
keybindCaptureTarget := "close"

settingsRerollsDropdown := 0
settingsBanishesDropdown := 0

commonRerollCheckbox := 0
rareRerollCheckbox := 0
epicRerollCheckbox := 0
legendaryRerollCheckbox := 0

; Special movable separator shown inside each upgrade priority list.
; Upgrades below this line are banish candidates when banishes remain.
BANISH_MARKER := "---BANISH---"
WEAPON_REROLL_MARKER := "---REROLL---"

rerollsPerLife := 0
banishesPerLife := 0
rerollsLeft := 0
banishesLeft := 0
banishedThisLife := []

rerollCommonEnabled := false
rerollRareEnabled := false
rerollEpicEnabled := false
rerollLegendaryEnabled := false

banishPic := 0
banishName := 0
banishType := 0
banishTolerance := 0
banishedLifeText := 0
lifeActionText := 0

; Native-control brushes used by the smooth dark theme.
darkWindowBrush := 0
darkControlBrush := 0

playCalibratedColor := "0xDEF5DE"
playAgainCalibratedColor := ""
giveUpCalibratedColor := ""

; Choice-card rarity colors.
commonRarityColor := "0x629962"
rareRarityColor := "0x547DB1"
epicRarityColor := "0xAE67B5"
legendaryRarityColor := "0xD8BC52"

; Weapon-only rarity colors.
; User supplied "FO2E1D"; hexadecimal uses zero, so this is F02E1D.
mythicRarityColor := "0xF02E1D"
limitedRarityColor := "0x9239BC"

rarityCalibrationSlotGui := 0
rarityCalibrationTarget := ""

commonEditPriority := []
rareEditPriority := []
epicEditPriority := []
legendaryEditPriority := []
weaponEditPriority := []

sessionDefaultTolerance := 15
lastDetailsGuiUpdate := 0

; Cache image-file existence after the first check.
; Choice scans can revisit the same category many times at higher
; tolerances, so there is no reason to ask Windows about the same
; PNG path over and over.
imageExistenceCache := Map()

; Per-run selection limits.
; Weapons are always capped at 5 selections each.
weaponRemaining := Map()

; Upgrade limits are user-configurable and saved.
; Remaining counts reset to the saved limits after death.
upgradeMaxSelections := Map()
upgradeRemaining := Map()
editUpgradeLimits := Map()

commonLimitControls := []
rareLimitControls := []
epicLimitControls := []
legendaryLimitControls := []

upgradeLimitOptions := [
    "1", "2", "3", "4", "5",
    "6", "7", "8", "9", "10",
    "11", "12", "13", "14", "15",
    "16", "17", "18", "19", "20"
]

; ============================================================
; WEAPON PRIORITY
; BEST weapon first, worst weapon last.
; ============================================================

weaponPriority := [
    "scythe",
    "ban_hammer",
    "trident",
    "firestaff",
    "revolver",
    "lightning_staff",
    "missile",
    "spike_ball",
    "axe",
    "bananarang",
    "daggers",
    "bow",
    "sword",
    "ninja_star",
    "frost_walker",
    "shotgun",
    "poison_flask",
    "aura",
    WEAPON_REROLL_MARKER
]

; ============================================================
; UPGRADE PRIORITY
; ============================================================

commonUpgrades := [
    "com_luck",
    "com_health",
    "com_damage",
    "com_attack_speed",
    "com_crit_chance",
    "com_regen",
    "com_move_speed",
    "com_proj_speed",
    BANISH_MARKER
]

rareUpgrades := [
    "stand_strong",
    "rare_luck",
    "rare_lifesteal",
    "rare_health",
    "demon_slayer",
    "rare_size",
    "rare_damage",
    "rare_armor",
    "rare_attack_speed",
    "thorns",
    "perilous_fervor",
    "blaze",
    "freeze",
    "piercing",
    "ricochet",
    "rare_crit_chance",
    "rare_regen",
    "rare_move_speed",
    "rare_proj_speed",
    "rare_xp",
    BANISH_MARKER
]

epicUpgrades := [
    "epic_proj_count",
    "bolt",
    "giants_strength",
    "epic_luck",
    "epic_lifesteal",
    "epic_health",
    "epic_size",
    "epic_damage",
    "epic_armor",
    "epic_attack_speed",
    "soul_of_swiftness",
    "epic_regen",
    "wind_blessing",
    "epic_move_speed",
    "epic_proj_speed",
    "epic_xp",
    BANISH_MARKER
]

legendaryUpgrades := [
    "multishot",
    "leg_proj_count",
    "power_trio",
    "leg_luck",
    "leg_damage",
    "leg_size",
    "leg_health",
    "leg_attack_speed",
    "leg_move_speed",
    "extra_jump",
    "leg_xp",
    BANISH_MARKER
]

; ============================================================
; SEARCH AREA
; ============================================================

 ; Default/fallback = widest 5-choice rectangle.
searchLeft := ScaleX(200)
searchTop := ScaleY(420)
searchRight := ScaleX(1720)
searchBottom := ScaleY(600)

userProfile := EnvGet("USERPROFILE")

; ============================================================
; PORTABLE ICONS FOLDER
; ============================================================
; Preferred layout:
;
;   SkinnyHub\
;       SkinnyHub.ahk
;       Icons\
;           upgrades\
;           Weapons\
;           restart\
;           settings\
;           720p\
;
; A_ScriptDir is the folder containing the running .ahk file, so the
; entire SkinnyHub folder can now be moved anywhere without breaking
; the image paths.
;
; Also supported:
;   - The script itself can be placed directly INSIDE the Icons folder.
;   - Old Downloads\Icons setups still work as a compatibility fallback.
; ============================================================

scriptFolder := A_ScriptDir
legacyIconsRoot := userProfile "\Downloads\Icons\"

iconsRoot := ""

; ============================================================
; YOUR NORMAL SETUP
; ============================================================
; Icons\
;   FinalSwarmMacro.ahk
;   upgrades\
;   Weapons\
;   restart\
;   settings\
;   ...
;
; Because the macro is INSIDE Icons, A_ScriptDir IS the Icons folder.
; The filename does not matter.
if (
    DirExist(A_ScriptDir "\upgrades")
    && DirExist(A_ScriptDir "\Weapons")
) {
    iconsRoot := A_ScriptDir "\"
}
; Also support putting the macro one folder ABOVE Icons:
;
; Folder\
;   FinalSwarmMacro.ahk
;   Icons\
;
else if (
    DirExist(A_ScriptDir "\Icons\upgrades")
    && DirExist(A_ScriptDir "\Icons\Weapons")
) {
    iconsRoot := A_ScriptDir "\Icons\"
}
; Backward compatibility with old versions.
else if (
    DirExist(legacyIconsRoot "upgrades")
    && DirExist(legacyIconsRoot "Weapons")
) {
    iconsRoot := legacyIconsRoot
}
else {
    ; Default the error/help text to the layout you use.
    iconsRoot := A_ScriptDir "\"
}

; ============================================================
; IMAGE SET SELECTION
; 1920x1080 uses the normal Icons folders.
; 1280x720 can use either:
;   1) Native 720p images in Icons\720p\
;   2) The 1080p images resized down automatically
; ============================================================

use720Mode := (A_ScreenWidth = 1280 && A_ScreenHeight = 720)

defaultUpgradeFolder := iconsRoot "upgrades\"
defaultWeaponFolder := iconsRoot "Weapons\"

native720UpgradeFolder := iconsRoot "720p\upgrades\"
native720WeaponFolder := iconsRoot "720p\Weapons\"

; Give a clear error instead of silently scanning a folder that does not exist.
if (
    !DirExist(defaultUpgradeFolder)
    || !DirExist(defaultWeaponFolder)
) {
    MsgBox(
        "FinalSwarmMacro could not find its image folders.`n`n"
        . "Your normal layout should be:`n"
        . A_ScriptDir "\FinalSwarmMacro.ahk`n"
        . A_ScriptDir "\upgrades\`n"
        . A_ScriptDir "\Weapons\`n"
        . A_ScriptDir "\restart\`n"
        . A_ScriptDir "\settings\`n`n"
        . "You can move the entire Icons folder anywhere and the macro will still work.",
        "FinalSwarmMacro - Icons Not Found",
        "Iconx"
    )
    ExitApp
}

native720Images := false

if (
    use720Mode
    && DirExist(native720UpgradeFolder)
    && DirExist(native720WeaponFolder)
) {
    upgradeFolder := native720UpgradeFolder
    weaponFolder := native720WeaponFolder
    native720Images := true
}
else {
    upgradeFolder := defaultUpgradeFolder
    weaponFolder := defaultWeaponFolder
}

; Weapon/upgrade screenshots were built around 140x140 cards.
; At 1280x720 the matching card size is about 93x93.
resizedCardSize720 := Round(140 * 1280 / 1920)

; Settings and restart.png now travel with the selected Icons folder too.
settingsFolder := iconsRoot "settings\"
settingsFile := settingsFolder "settings.ini"

restartFolder := iconsRoot "restart\"
restartImage := restartFolder "restart.png"

if !DirExist(settingsFolder)
    DirCreate settingsFolder

; ============================================================
; APP / INTERFACE SETTINGS
; ============================================================

closeScriptHotkey := IniRead(
    settingsFile,
    "Interface",
    "CloseHotkey",
    "\"
)

if Trim(closeScriptHotkey) = ""
    closeScriptHotkey := "\"

pauseScriptHotkey := IniRead(
    settingsFile,
    "Interface",
    "PauseHotkey",
    "P"
)

if Trim(pauseScriptHotkey) = ""
    pauseScriptHotkey := "P"

darkModeEnabled := (
    IniRead(
        settingsFile,
        "Interface",
        "DarkMode",
        "0"
    ) = "1"
)

; ============================================================
; REROLL / BANISH SETTINGS
; ============================================================

try {
    rerollsPerLife := Integer(
        IniRead(settingsFile, "Actions", "RerollsPerLife", "0")
    )
}
catch {
    rerollsPerLife := 0
}

if rerollsPerLife < 0
    rerollsPerLife := 0
else if rerollsPerLife > 3
    rerollsPerLife := 3

try {
    banishesPerLife := Integer(
        IniRead(settingsFile, "Actions", "BanishesPerLife", "0")
    )
}
catch {
    banishesPerLife := 0
}

if banishesPerLife < 0
    banishesPerLife := 0
else if banishesPerLife > 2
    banishesPerLife := 2

rerollsLeft := rerollsPerLife
banishesLeft := banishesPerLife
banishedThisLife := []

rerollCommonEnabled := (
    IniRead(settingsFile, "RerollByRarity", "Common", "0") = "1"
)
rerollRareEnabled := (
    IniRead(settingsFile, "RerollByRarity", "Rare", "0") = "1"
)
rerollEpicEnabled := (
    IniRead(settingsFile, "RerollByRarity", "Epic", "0") = "1"
)
rerollLegendaryEnabled := (
    IniRead(settingsFile, "RerollByRarity", "Legendary", "0") = "1"
)

; ============================================================
; RESTART / PLAY CALIBRATION SETTINGS
; ============================================================
; Play has a default. Play Again / Give Up and rarity colors can be calibrated.

playCalibratedColor := IniRead(
    settingsFile,
    "Calibration",
    "Play",
    "0xDEF5DE"
)

playAgainCalibratedColor := IniRead(
    settingsFile,
    "Calibration",
    "PlayAgain",
    ""
)

giveUpCalibratedColor := IniRead(
    settingsFile,
    "Calibration",
    "GiveUp",
    ""
)

commonRarityColor := IniRead(
    settingsFile,
    "Calibration",
    "Common",
    "0x629962"
)

rareRarityColor := IniRead(
    settingsFile,
    "Calibration",
    "Rare",
    "0x547DB1"
)

epicRarityColor := IniRead(
    settingsFile,
    "Calibration",
    "Epic",
    "0xAE67B5"
)

legendaryRarityColor := IniRead(
    settingsFile,
    "Calibration",
    "Legendary",
    "0xD8BC52"
)

mythicRarityColor := IniRead(
    settingsFile,
    "Calibration",
    "Mythic",
    "0xF02E1D"
)

limitedRarityColor := IniRead(
    settingsFile,
    "Calibration",
    "Limited",
    "0x9239BC"
)

if !RegExMatch(playCalibratedColor, "i)^0x[0-9A-F]{6}$")
    playCalibratedColor := "0xDEF5DE"

if playAgainCalibratedColor != ""
&& !RegExMatch(playAgainCalibratedColor, "i)^0x[0-9A-F]{6}$")
    playAgainCalibratedColor := ""

if giveUpCalibratedColor != ""
&& !RegExMatch(giveUpCalibratedColor, "i)^0x[0-9A-F]{6}$")
    giveUpCalibratedColor := ""

if !RegExMatch(commonRarityColor, "i)^0x[0-9A-F]{6}$")
    commonRarityColor := "0x629962"

if !RegExMatch(rareRarityColor, "i)^0x[0-9A-F]{6}$")
    rareRarityColor := "0x547DB1"

if !RegExMatch(epicRarityColor, "i)^0x[0-9A-F]{6}$")
    epicRarityColor := "0xAE67B5"

if !RegExMatch(legendaryRarityColor, "i)^0x[0-9A-F]{6}$")
    legendaryRarityColor := "0xD8BC52"

if !RegExMatch(mythicRarityColor, "i)^0x[0-9A-F]{6}$")
    mythicRarityColor := "0xF02E1D"

if !RegExMatch(limitedRarityColor, "i)^0x[0-9A-F]{6}$")
    limitedRarityColor := "0x9239BC"


; ============================================================
; GUI THEME HELPERS
; ============================================================

ThemeFontOptions(baseOptions := "") {

    global darkModeEnabled

    return baseOptions
        . (darkModeEnabled ? " cF2F2F2" : " c202020")
}

RgbHexToColorRef(rgbHex) {

    rgb := Integer("0x" rgbHex)

    ; Windows COLORREF is 0x00BBGGRR rather than 0xRRGGBB.
    return (
        ((rgb & 0xFF0000) >> 16)
        | (rgb & 0x00FF00)
        | ((rgb & 0x0000FF) << 16)
    )
}

GetWindowClassName(hwnd) {

    if !hwnd
        return ""

    classBuffer := Buffer(256 * 2, 0)

    length := DllCall(
        "user32\GetClassNameW",
        "Ptr", hwnd,
        "Ptr", classBuffer,
        "Int", 256,
        "Int"
    )

    if length <= 0
        return ""

    return StrGet(classBuffer, length, "UTF-16")
}

EnsureDarkThemeBrushes() {

    global darkWindowBrush
    global darkControlBrush

    if !darkWindowBrush {
        darkWindowBrush := DllCall(
            "gdi32\CreateSolidBrush",
            "UInt", RgbHexToColorRef("1E1E1E"),
            "Ptr"
        )
    }

    if !darkControlBrush {
        darkControlBrush := DllCall(
            "gdi32\CreateSolidBrush",
            "UInt", RgbHexToColorRef("292929"),
            "Ptr"
        )
    }
}

DarkGuiControlColor(wParam, lParam, msg, hwnd) {

    global darkModeEnabled
    global darkWindowBrush
    global darkControlBrush

    if !darkModeEnabled
        return

    EnsureDarkThemeBrushes()

    hdc := wParam
    controlHwnd := lParam

    className := GetWindowClassName(controlHwnd)

    parentHwnd := 0
    parentClass := ""

    try {
        parentHwnd := DllCall(
            "user32\GetParent",
            "Ptr", controlHwnd,
            "Ptr"
        )

        if parentHwnd
            parentClass := GetWindowClassName(parentHwnd)
    }

    isInputSurface := (
        msg = 0x0133                         ; WM_CTLCOLOREDIT
        || msg = 0x0134                     ; WM_CTLCOLORLISTBOX
        || className = "Edit"
        || className = "ComboBox"
        || className = "ListBox"
        || parentClass = "ComboBox"
    )

    DllCall(
        "gdi32\SetTextColor",
        "Ptr", hdc,
        "UInt", RgbHexToColorRef("F2F2F2")
    )

    if isInputSurface {

        DllCall(
            "gdi32\SetBkMode",
            "Ptr", hdc,
            "Int", 2                        ; OPAQUE
        )

        DllCall(
            "gdi32\SetBkColor",
            "Ptr", hdc,
            "UInt", RgbHexToColorRef("292929")
        )

        return darkControlBrush
    }

    ; Normal labels use the same background as the GUI itself.
    DllCall(
        "gdi32\SetBkMode",
        "Ptr", hdc,
        "Int", 1                            ; TRANSPARENT
    )

    return darkWindowBrush
}

InitializeDarkControlPainting() {

    EnsureDarkThemeBrushes()

    ; Standard editable controls.
    OnMessage(0x0133, DarkGuiControlColor)  ; WM_CTLCOLOREDIT

    ; ListBoxes and the drop-down portion of ComboBoxes/DDLs.
    OnMessage(0x0134, DarkGuiControlColor)  ; WM_CTLCOLORLISTBOX

    ; Buttons / GroupBoxes / CheckBoxes.
    ; GroupBox captions are what Windows was repainting black in dark
    ; mode (Common/Rare/Epic/Legendary, Choice 1, Best Choice, Banish).
    OnMessage(0x0135, DarkGuiControlColor)  ; WM_CTLCOLORBTN

    ; Static controls AND read-only Edit controls.
    ; Read-only Edit controls are important here because the Calibration
    ; saved-color boxes and Settings keybind box use this message.
    OnMessage(0x0138, DarkGuiControlColor)  ; WM_CTLCOLORSTATIC
}

SetGuiBaseTheme(guiObj) {

    global darkModeEnabled

    if !IsObject(guiObj)
        return

    ; Softer dark gray instead of pure black.
    guiObj.BackColor := darkModeEnabled ? "1E1E1E" : "F0F0F0"
}

ApplyThemeToControl(controlObj) {

    global darkModeEnabled

    if !IsObject(controlObj)
        return

    fontColor := darkModeEnabled ? "F2F2F2" : "202020"

    try controlObj.SetFont("c" fontColor)

    className := GetWindowClassName(controlObj.Hwnd)

    ; GroupBoxes are BUTTON-class controls with BS_GROUPBOX (0x7).
    ; Windows' Explorer dark theme can still paint their caption black,
    ; so detect them and let our WM_CTLCOLORBTN handler paint the text.
    controlStyle := 0

    try {
        controlStyle := DllCall(
            "user32\GetWindowLongPtrW",
            "Ptr", controlObj.Hwnd,
            "Int", -16,                    ; GWL_STYLE
            "Ptr"
        )
    }

    isGroupBox := (
        className = "Button"
        && (controlStyle & 0xF) = 0x7       ; BS_GROUPBOX
    )

    if darkModeEnabled {

        if isGroupBox {

            ; Disable the visual-style renderer for GroupBoxes so it
            ; cannot override our light caption color with black.
            try DllCall(
                "uxtheme\SetWindowTheme",
                "Ptr", controlObj.Hwnd,
                "WStr", "",
                "WStr", ""
            )

            try controlObj.SetFont("cF2F2F2")
        }
        ; Edit and ComboBox controls respond better to the CFD dark theme.
        else if (
            className = "Edit"
            || className = "ComboBox"
        ) {
            try DllCall(
                "uxtheme\SetWindowTheme",
                "Ptr", controlObj.Hwnd,
                "WStr", "DarkMode_CFD",
                "Ptr", 0
            )
        }
        else {
            try DllCall(
                "uxtheme\SetWindowTheme",
                "Ptr", controlObj.Hwnd,
                "WStr", "DarkMode_Explorer",
                "Ptr", 0
            )
        }
    }
    else {

        ; Restore normal Windows light-control styling.
        try DllCall(
            "uxtheme\SetWindowTheme",
            "Ptr", controlObj.Hwnd,
            "WStr", "Explorer",
            "Ptr", 0
        )
    }

    ; Force Windows to repaint the full control after a live theme switch.
    try DllCall(
        "user32\RedrawWindow",
        "Ptr", controlObj.Hwnd,
        "Ptr", 0,
        "Ptr", 0,
        "UInt", 0x0405                    ; INVALIDATE | ERASE | FRAME
    )
}

ApplyThemeToGui(guiObj) {

    global darkModeEnabled

    if !IsObject(guiObj)
        return

    SetGuiBaseTheme(guiObj)

    ; Apply both text color and native dark-control style.
    try {
        for controlHwnd, controlObj in guiObj
            ApplyThemeToControl(controlObj)
    }

    ; Dark/light title bar.
    darkValue := Buffer(4, 0)
    NumPut("Int", darkModeEnabled ? 1 : 0, darkValue)

    ; Attribute 20 is used by current Windows 10/11 builds.
    ; Attribute 19 is kept as a compatibility fallback.
    try {
        result := DllCall(
            "dwmapi\DwmSetWindowAttribute",
            "Ptr", guiObj.Hwnd,
            "Int", 20,
            "Ptr", darkValue,
            "Int", 4,
            "Int"
        )

        if result != 0 {
            DllCall(
                "dwmapi\DwmSetWindowAttribute",
                "Ptr", guiObj.Hwnd,
                "Int", 19,
                "Ptr", darkValue,
                "Int", 4,
                "Int"
            )
        }
    }

    try DllCall(
        "user32\RedrawWindow",
        "Ptr", guiObj.Hwnd,
        "Ptr", 0,
        "Ptr", 0,
        "UInt", 0x0485                    ; ALLCHILDREN + INVALIDATE + ERASE + FRAME
    )
}

ApplyThemeToAllGuis() {

    global farmGui
    global calibrationGui
    global rarityCalibrationSlotGui
    global choiceGui
    global pauseGui
    global priorityGui
    global settingsGui
    global keybindCaptureGui

    guiList := [
        farmGui,
        calibrationGui,
        rarityCalibrationSlotGui,
        choiceGui,
        pauseGui,
        priorityGui,
        settingsGui,
        keybindCaptureGui
    ]

    for guiObj in guiList {
        if IsObject(guiObj)
            ApplyThemeToGui(guiObj)
    }
}

InitializeDarkControlPainting()

commonDefaults := CopyArray(commonUpgrades)
rareDefaults := CopyArray(rareUpgrades)
epicDefaults := CopyArray(epicUpgrades)
legendaryDefaults := CopyArray(legendaryUpgrades)
weaponDefaults := CopyArray(weaponPriority)

commonUpgrades := LoadPriority("Common", commonDefaults)
rareUpgrades := LoadPriority("Rare", rareDefaults)
epicUpgrades := LoadPriority("Epic", epicDefaults)
legendaryUpgrades := LoadPriority("Legendary", legendaryDefaults)
weaponPriority := LoadPriority("Weapons", weaponDefaults)

upgradeMaxSelections := LoadUpgradeLimits()
ResetSelectionCounts()
ResetLifeActionCounts()


; ============================================================
; MAIN GUI
; ============================================================

farmGui := Gui("+AlwaysOnTop +Border", "Farming")
SetGuiBaseTheme(farmGui)
farmGui.SetFont(
    ThemeFontOptions(use720Mode ? "s8" : "s10"),
    "Segoe UI"
)

islandOptions := [
    "Grasslands",
    "Desert",
    "Swamp",
    "Jungle",
    "Frost Forest"
]

challengeOptions := [
    "None",
    "Double Trouble"
]

difficultyOptions := [
    "Normal",
    "Hard",
    "Nightmare"
]

toleranceOptions := [
    "15",
    "30",
    "45",
    "60",
    "75",
    "90",
    "105",
    "120",
    "135",
    "150",
    "165",
    "180",
    "195",
    "210",
    "225",
    "240"
]

farmGui.AddText("xm", "Island:")

islandDropdown := farmGui.AddDropDownList(
    "xm w" GS(180) " Choose1",
    islandOptions
)

farmGui.AddText("xm y+" GS(15), "Challenge:")

challengeDropdown := farmGui.AddDropDownList(
    "xm w" GS(180) " Choose1",
    challengeOptions
)

farmGui.AddText("xm y+" GS(15), "Difficulty:")

difficultyDropdown := farmGui.AddDropDownList(
    "xm w" GS(180) " Choose1",
    difficultyOptions
)

farmGui.AddText("xm y+" GS(15), "Default Tolerance:")

defaultToleranceDropdown := farmGui.AddDropDownList(
    "xm w" GS(180) " Choose1",
    toleranceOptions
)

LoadSavedSelections()

islandDropdown.OnEvent("Change", SaveSelections)
challengeDropdown.OnEvent("Change", SaveSelections)
difficultyDropdown.OnEvent("Change", SaveSelections)
defaultToleranceDropdown.OnEvent("Change", DefaultToleranceChanged)

resolutionText := farmGui.AddText(
    "xm y+" GS(15) " w" GS(180),
    "Resolution: " A_ScreenWidth "x" A_ScreenHeight
)

scaleText := farmGui.AddText(
    "xm y+" GS(5) " w" GS(180),
    "Scale: " scalePercent "%"
)

imageModeText := farmGui.AddText(
    "xm y+" GS(5) " w" GS(180),
    native720Images ? "Image Set: 720p native" : (use720Mode ? "Image Set: 1080p -> 720p" : "Image Set: 1080p")
)

toleranceText := farmGui.AddText(
    "xm y+" GS(5) " w" GS(180),
    "Base Tolerance: *" sessionDefaultTolerance
)

prioritiesButton := farmGui.AddButton(
    "xm y+" GS(10) " w" GS(180) " h" GS(35),
    "Priorities"
)

prioritiesButton.OnEvent("Click", OpenPriorities)

calibrateButton := farmGui.AddButton(
    "xm y+" GS(8) " w" GS(180) " h" GS(35),
    "Calibrate"
)

calibrateButton.OnEvent("Click", OpenCalibrationGui)

settingsButton := farmGui.AddButton(
    "xm y+" GS(8) " w" GS(180) " h" GS(35),
    "Settings"
)

settingsButton.OnEvent("Click", OpenSettings)

startButton := farmGui.AddButton(
    "xm y+" GS(8) " w" GS(180) " h" GS(35),
    "Start"
)

startButton.OnEvent("Click", StartFarm)

ApplyThemeToGui(farmGui)

farmGui.Show("x" guiX " y" guiY " AutoSize")

CreateCalibrationGui()
CreateChoiceGui()
CreatePauseGui()
UpdateToleranceDisplays()
ResetChoiceGui()

; ============================================================
; CALIBRATION GUI
; ============================================================

; ============================================================
; PAUSE GUI
; ============================================================

CreatePauseGui() {

    global pauseGui
    global pauseToleranceDropdown
    global toleranceOptions
    global sessionDefaultTolerance
    global use720Mode

    pauseGui := Gui(
        "+AlwaysOnTop +Border -SysMenu",
        "Farming Paused"
    )

    SetGuiBaseTheme(pauseGui)

    pauseGui.SetFont(
        ThemeFontOptions(use720Mode ? "s8" : "s10"),
        "Segoe UI"
    )

    pauseGui.AddText(
        "xm ym w" GS(190) " Center",
        "Farming paused"
    )

    pauseGui.AddText(
        "xm y+" GS(10) " w" GS(190),
        "Tolerance:"
    )

    pauseToleranceDropdown := pauseGui.AddDropDownList(
        "xm y+" GS(4) " w" GS(190),
        toleranceOptions
    )

    ChooseSavedItem(
        pauseToleranceDropdown,
        toleranceOptions,
        sessionDefaultTolerance
    )

    pauseToleranceDropdown.OnEvent(
        "Change",
        PauseToleranceChanged
    )

    pausePrioritiesButton := pauseGui.AddButton(
        "xm y+" GS(10) " w" GS(190) " h" GS(32),
        "Priorities"
    )

    pauseCalibrateButton := pauseGui.AddButton(
        "xm y+" GS(7) " w" GS(190) " h" GS(32),
        "Calibrate"
    )

    pauseSettingsButton := pauseGui.AddButton(
        "xm y+" GS(7) " w" GS(190) " h" GS(32),
        "Settings"
    )

    pauseResumeButton := pauseGui.AddButton(
        "xm y+" GS(12) " w" GS(190) " h" GS(38) " Default",
        "Resume"
    )

    pausePrioritiesButton.OnEvent("Click", OpenPriorities)
    pauseCalibrateButton.OnEvent("Click", OpenCalibrationGui)
    pauseSettingsButton.OnEvent("Click", OpenSettings)
    pauseResumeButton.OnEvent("Click", ResumeFarmFromPause)

    ApplyThemeToGui(pauseGui)

    pauseGui.Show(
        "w" GS(210)
        . " h" GS(255)
        . " Hide"
    )

    PositionPauseGuiTopRight()
}


PositionPauseGuiTopRight() {

    global pauseGui

    if !IsObject(pauseGui)
        return

    oldDetectHidden := A_DetectHiddenWindows
    DetectHiddenWindows true

    try {
        WinGetPos(
            &currentX,
            &currentY,
            &windowWidth,
            &windowHeight,
            "ahk_id " pauseGui.Hwnd
        )

        pauseX := A_ScreenWidth - windowWidth

        WinMove(
            pauseX,
            0,
            ,
            ,
            "ahk_id " pauseGui.Hwnd
        )
    }
    finally {
        DetectHiddenWindows oldDetectHidden
    }
}


ShowPauseGui() {

    global pauseGui
    global pauseToleranceDropdown
    global toleranceOptions
    global sessionDefaultTolerance

    if !IsObject(pauseGui)
        return

    if IsObject(pauseToleranceDropdown) {
        ChooseSavedItem(
            pauseToleranceDropdown,
            toleranceOptions,
            sessionDefaultTolerance
        )
    }

    ApplyThemeToGui(pauseGui)
    pauseGui.Show()
    PositionPauseGuiTopRight()
}


PauseToleranceChanged(*) {

    global pauseToleranceDropdown
    global defaultToleranceDropdown
    global toleranceOptions
    global sessionDefaultTolerance

    if !IsObject(pauseToleranceDropdown)
        return

    sessionDefaultTolerance := Integer(pauseToleranceDropdown.Text)

    if IsObject(defaultToleranceDropdown) {
        ChooseSavedItem(
            defaultToleranceDropdown,
            toleranceOptions,
            pauseToleranceDropdown.Text
        )
    }

    SaveSelections()
    UpdateToleranceDisplays()
}


HidePauseUtilityGuis() {

    global calibrationGui
    global rarityCalibrationSlotGui
    global priorityGui
    global settingsGui
    global keybindCaptureGui
    global prioritiesButton
    global settingsButton

    if IsObject(calibrationGui)
        calibrationGui.Hide()

    if IsObject(rarityCalibrationSlotGui)
        rarityCalibrationSlotGui.Hide()

    if IsObject(priorityGui)
        priorityGui.Hide()

    if IsObject(settingsGui)
        settingsGui.Hide()

    if IsObject(keybindCaptureGui)
        keybindCaptureGui.Hide()

    if IsObject(prioritiesButton)
        prioritiesButton.Enabled := true

    if IsObject(settingsButton)
        settingsButton.Enabled := true
}

CreateCalibrationGui() {

    global calibrationGui
    global use720Mode

    global playCalibratedColor
    global playAgainCalibratedColor
    global giveUpCalibratedColor

    global commonRarityColor
    global rareRarityColor
    global epicRarityColor
    global legendaryRarityColor
    global mythicRarityColor
    global limitedRarityColor

    global playCalibrationValueText
    global playAgainCalibrationValueText
    global giveUpCalibrationValueText

    global commonCalibrationValueText
    global rareCalibrationValueText
    global epicCalibrationValueText
    global legendaryCalibrationValueText
    global mythicCalibrationValueText
    global limitedCalibrationValueText

    global calibrationStatusText

    calibrationGui := Gui("+AlwaysOnTop +Border", "Calibration")
    SetGuiBaseTheme(calibrationGui)
    calibrationGui.SetFont(
        ThemeFontOptions(use720Mode ? "s7" : "s8"),
        "Segoe UI"
    )

    calibrationGui.AddText(
        "x" GS(8) " y" GS(6) " w" GS(324) " Center",
        "Calibration"
    )

    calibrationGui.AddText("x" GS(10) " y" GS(28) " w" GS(72), "Play")
    playCalibrationValueText := calibrationGui.AddEdit(
        "x" GS(82) " y" GS(24) " w" GS(100) " ReadOnly",
        playCalibratedColor
    )
    playCalibrationButton := calibrationGui.AddButton(
        "x" GS(190) " y" GS(23) " w" GS(132) " h" GS(24),
        "Calibrate Play"
    )
    playCalibrationButton.OnEvent("Click", CalibratePlayColor)

    calibrationGui.AddText("x" GS(10) " y" GS(56) " w" GS(72), "Play Again")
    playAgainCalibrationValueText := calibrationGui.AddEdit(
        "x" GS(82) " y" GS(52) " w" GS(100) " ReadOnly",
        playAgainCalibratedColor = "" ? "Not set" : playAgainCalibratedColor
    )

    calibrationGui.AddText("x" GS(10) " y" GS(84) " w" GS(72), "Give Up")
    giveUpCalibrationValueText := calibrationGui.AddEdit(
        "x" GS(82) " y" GS(80) " w" GS(100) " ReadOnly",
        giveUpCalibratedColor = "" ? "Not set" : giveUpCalibratedColor
    )

    playAgainCalibrationButton := calibrationGui.AddButton(
        "x" GS(190) " y" GS(51) " w" GS(132) " h" GS(25),
        "Calibrate Play Again"
    )
    playAgainCalibrationButton.OnEvent(
        "Click",
        CalibratePlayAgain
    )

    giveUpCalibrationButton := calibrationGui.AddButton(
        "x" GS(190) " y" GS(79) " w" GS(132) " h" GS(25),
        "Calibrate Give Up"
    )
    giveUpCalibrationButton.OnEvent(
        "Click",
        CalibrateGiveUp
    )

    calibrationGui.AddText(
        "x" GS(8) " y" GS(111) " w" GS(324) " Center",
        "Choice rarity colors"
    )

    rarityRows := [
        ["Common", "common", 132],
        ["Rare", "rare", 160],
        ["Epic", "epic", 188],
        ["Legendary", "legendary", 216],
        ["Mythic", "mythic", 244],
        ["Limited", "limited", 272]
    ]

    for row in rarityRows {

        label := row[1]
        rarity := row[2]
        y := row[3]

        calibrationGui.AddText(
            "x" GS(10) " y" GS(y + 4) " w" GS(70),
            label
        )

        switch rarity {
            case "common":
                commonCalibrationValueText := calibrationGui.AddEdit(
                    "x" GS(82) " y" GS(y) " w" GS(100) " ReadOnly",
                    commonRarityColor
                )
            case "rare":
                rareCalibrationValueText := calibrationGui.AddEdit(
                    "x" GS(82) " y" GS(y) " w" GS(100) " ReadOnly",
                    rareRarityColor
                )
            case "epic":
                epicCalibrationValueText := calibrationGui.AddEdit(
                    "x" GS(82) " y" GS(y) " w" GS(100) " ReadOnly",
                    epicRarityColor
                )
            case "legendary":
                legendaryCalibrationValueText := calibrationGui.AddEdit(
                    "x" GS(82) " y" GS(y) " w" GS(100) " ReadOnly",
                    legendaryRarityColor
                )
            case "mythic":
                mythicCalibrationValueText := calibrationGui.AddEdit(
                    "x" GS(82) " y" GS(y) " w" GS(100) " ReadOnly",
                    mythicRarityColor
                )
            case "limited":
                limitedCalibrationValueText := calibrationGui.AddEdit(
                    "x" GS(82) " y" GS(y) " w" GS(100) " ReadOnly",
                    limitedRarityColor
                )
        }

        rarityButton := calibrationGui.AddButton(
            "x" GS(190) " y" GS(y - 1) " w" GS(132) " h" GS(24),
            "Calibrate"
        )

        rarityButton.OnEvent(
            "Click",
            StartRaritySlotCalibration.Bind(rarity)
        )
    }

    calibrationStatusText := calibrationGui.AddText(
        "x" GS(8) " y" GS(304) " w" GS(324) " Center",
        "Ready"
    )

    calibrationGui.OnEvent("Close", HideCalibrationGui)

    ApplyThemeToGui(calibrationGui)

    calibrationGui.Show(
        "w" GS(340)
        . " h" GS(328)
        . " Hide"
    )

    CreateRarityCalibrationSlotGui()
}

OpenCalibrationGui(*) {

    global calibrationGui

    global playCalibratedColor
    global playAgainCalibratedColor
    global giveUpCalibratedColor

    global commonRarityColor
    global rareRarityColor
    global epicRarityColor
    global legendaryRarityColor
    global mythicRarityColor
    global limitedRarityColor

    global playCalibrationValueText
    global playAgainCalibrationValueText
    global giveUpCalibrationValueText

    global commonCalibrationValueText
    global rareCalibrationValueText
    global epicCalibrationValueText
    global legendaryCalibrationValueText
    global mythicCalibrationValueText
    global limitedCalibrationValueText

    global calibrationStatusText

    if !IsObject(calibrationGui)
        CreateCalibrationGui()

    playCalibrationValueText.Value := playCalibratedColor
    playAgainCalibrationValueText.Value :=
        playAgainCalibratedColor = "" ? "Not set" : playAgainCalibratedColor
    giveUpCalibrationValueText.Value :=
        giveUpCalibratedColor = "" ? "Not set" : giveUpCalibratedColor

    commonCalibrationValueText.Value := commonRarityColor
    rareCalibrationValueText.Value := rareRarityColor
    epicCalibrationValueText.Value := epicRarityColor
    legendaryCalibrationValueText.Value := legendaryRarityColor
    mythicCalibrationValueText.Value := mythicRarityColor
    limitedCalibrationValueText.Value := limitedRarityColor

    calibrationStatusText.Text := "Ready"

    ; Keep Calibration out of the game-selection area.
    ; Scaled coordinates preserve the same top-left placement at 720p.
    calibrationGui.Show(
        "x" ScaleX(20)
        . " y" ScaleY(20)
        . " w" GS(340)
        . " h" GS(328)
    )
}

HideCalibrationGui(*) {

    global calibrationGui

    if IsObject(calibrationGui)
        calibrationGui.Hide()

    return true
}

CreateRarityCalibrationSlotGui() {

    global rarityCalibrationSlotGui
    global use720Mode
    global rarityCalibrationInstructionText

    rarityCalibrationSlotGui := Gui(
        "+AlwaysOnTop +Border",
        "Rarity Slot Calibration"
    )

    SetGuiBaseTheme(rarityCalibrationSlotGui)
    rarityCalibrationSlotGui.SetFont(
        ThemeFontOptions(use720Mode ? "s7" : "s8"),
        "Segoe UI"
    )

    rarityCalibrationInstructionText := rarityCalibrationSlotGui.AddText(
        "x" GS(10)
        . " y" GS(8)
        . " w" GS(410)
        . " h" GS(48)
        . " Center",
        ""
    )

    Loop 5 {
        slot := A_Index
        buttonX := 10 + ((slot - 1) * 82)

        slotButton := rarityCalibrationSlotGui.AddButton(
            "x" GS(buttonX)
            . " y" GS(62)
            . " w" GS(74)
            . " h" GS(30),
            "Slot " slot
        )

        slotButton.OnEvent(
            "Click",
            CalibrateRarityFromSlot.Bind(slot)
        )
    }

    cancelButton := rarityCalibrationSlotGui.AddButton(
        "x" GS(155)
        . " y" GS(101)
        . " w" GS(110)
        . " h" GS(26),
        "Cancel"
    )

    cancelButton.OnEvent("Click", CancelRaritySlotCalibration)
    rarityCalibrationSlotGui.OnEvent("Close", CancelRaritySlotCalibration)

    ApplyThemeToGui(rarityCalibrationSlotGui)

    rarityCalibrationSlotGui.Show(
        "w" GS(430)
        . " h" GS(137)
        . " Hide"
    )
}

StartRaritySlotCalibration(rarity, *) {

    global calibrationGui
    global rarityCalibrationSlotGui
    global rarityCalibrationInstructionText
    global rarityCalibrationTarget

    rarityCalibrationTarget := rarity

    if IsObject(calibrationGui)
        calibrationGui.Hide()

    displayName := StrUpper(SubStr(rarity, 1, 1))
        . SubStr(rarity, 2)

    rarityCalibrationInstructionText.Text :=
        "Have a choice screen open in-game. "
        . "Click the slot that currently has the "
        . displayName
        . " color.`nDo NOT calibrate rarity colors when there are 4 choices."

    guiWidth := GS(430)
    guiX := Round((A_ScreenWidth - guiWidth) / 2)
    guiY := ScaleY(20)

    rarityCalibrationSlotGui.Show(
        "x" guiX
        . " y" guiY
        . " w" guiWidth
        . " h" GS(137)
    )
}

GetFiveChoiceCalibrationX(slot) {

    switch slot {
        case 1:
            return 290
        case 2:
            return 625
        case 3:
            return 960
        case 4:
            return 1295
        case 5:
            return 1630
    }

    return 960
}

CalibrateRarityFromSlot(slot, *) {

    global rarityCalibrationTarget
    global rarityCalibrationSlotGui
    global calibrationGui
    global settingsFile
    global calibrationStatusText

    global commonRarityColor
    global rareRarityColor
    global epicRarityColor
    global legendaryRarityColor
    global mythicRarityColor
    global limitedRarityColor

    global commonCalibrationValueText
    global rareCalibrationValueText
    global epicCalibrationValueText
    global legendaryCalibrationValueText
    global mythicCalibrationValueText
    global limitedCalibrationValueText

    sampleX := ScaleX(GetFiveChoiceCalibrationX(slot))
    sampleY := ScaleY(355)

    sampledColor := PixelGetColor(
        sampleX,
        sampleY,
        "RGB"
    ) & 0xFFFFFF

    formattedColor := Format("0x{:06X}", sampledColor)

    switch rarityCalibrationTarget {
        case "common":
            commonRarityColor := formattedColor
            commonCalibrationValueText.Value := formattedColor
            IniWrite formattedColor, settingsFile, "Calibration", "Common"
        case "rare":
            rareRarityColor := formattedColor
            rareCalibrationValueText.Value := formattedColor
            IniWrite formattedColor, settingsFile, "Calibration", "Rare"
        case "epic":
            epicRarityColor := formattedColor
            epicCalibrationValueText.Value := formattedColor
            IniWrite formattedColor, settingsFile, "Calibration", "Epic"
        case "legendary":
            legendaryRarityColor := formattedColor
            legendaryCalibrationValueText.Value := formattedColor
            IniWrite formattedColor, settingsFile, "Calibration", "Legendary"
        case "mythic":
            mythicRarityColor := formattedColor
            mythicCalibrationValueText.Value := formattedColor
            IniWrite formattedColor, settingsFile, "Calibration", "Mythic"
        case "limited":
            limitedRarityColor := formattedColor
            limitedCalibrationValueText.Value := formattedColor
            IniWrite formattedColor, settingsFile, "Calibration", "Limited"
    }

    calibrationStatusText.Text :=
        "Saved "
        . rarityCalibrationTarget
        . " from Slot "
        . slot
        . ": "
        . formattedColor

    rarityCalibrationTarget := ""

    if IsObject(rarityCalibrationSlotGui)
        rarityCalibrationSlotGui.Hide()

    if IsObject(calibrationGui)
        calibrationGui.Show()
}

CancelRaritySlotCalibration(*) {

    global rarityCalibrationTarget
    global rarityCalibrationSlotGui
    global calibrationGui

    rarityCalibrationTarget := ""

    if IsObject(rarityCalibrationSlotGui)
        rarityCalibrationSlotGui.Hide()

    if IsObject(calibrationGui)
        calibrationGui.Show()

    return true
}

CalibratePlayColor(*) {

    global playCalibratedColor
    global playCalibrationValueText
    global calibrationStatusText
    global settingsFile

    ; 1080p baseline coordinate supplied by the user.
    ; ScaleX/ScaleY keeps the same logical point on 1280x720.
    sampleX := ScaleX(932)
    sampleY := ScaleY(1010)

    sampledColor := PixelGetColor(sampleX, sampleY, "RGB")
    playCalibratedColor := Format("0x{:06X}", sampledColor)

    playCalibrationValueText.Value := playCalibratedColor

    IniWrite(
        playCalibratedColor,
        settingsFile,
        "Calibration",
        "Play"
    )

    calibrationStatusText.Text := "Play saved: " playCalibratedColor "  (" sampleX ", " sampleY ")"
}

CalibratePlayAgain(*) {

    global playAgainCalibratedColor
    global playAgainCalibrationValueText
    global calibrationStatusText
    global settingsFile

    ; Use the EXACT same pixel the death restart waits on.
    playAgainX := ScaleX(964)
    playAgainY := ScaleY(1020)

    playAgainColor := PixelGetColor(
        playAgainX,
        playAgainY,
        "RGB"
    ) & 0xFFFFFF

    playAgainCalibratedColor := Format(
        "0x{:06X}",
        playAgainColor
    )

    playAgainCalibrationValueText.Value :=
        playAgainCalibratedColor

    IniWrite(
        playAgainCalibratedColor,
        settingsFile,
        "Calibration",
        "PlayAgain"
    )

    calibrationStatusText.Text :=
        "Play Again saved: "
        . playAgainCalibratedColor
        . "  ("
        . playAgainX
        . ", "
        . playAgainY
        . ")"
}

CalibrateGiveUp(*) {

    global giveUpCalibratedColor
    global giveUpCalibrationValueText
    global calibrationStatusText
    global settingsFile

    ; Use the EXACT same pixel as death/restart detection.
    giveUpX := ScaleX(1074)
    giveUpY := ScaleY(1030)

    giveUpColor := PixelGetColor(
        giveUpX,
        giveUpY,
        "RGB"
    ) & 0xFFFFFF

    giveUpCalibratedColor := Format(
        "0x{:06X}",
        giveUpColor
    )

    giveUpCalibrationValueText.Value :=
        giveUpCalibratedColor

    IniWrite(
        giveUpCalibratedColor,
        settingsFile,
        "Calibration",
        "GiveUp"
    )

    calibrationStatusText.Text :=
        "Give Up saved: "
        . giveUpCalibratedColor
        . "  ("
        . giveUpX
        . ", "
        . giveUpY
        . ")"
}


; ============================================================
; CHOICE GUI
; ============================================================

CreateChoiceGui() {

    global choiceGui
    global choiceGuiX
    global choiceGuiY
    global choiceGuiWidthBase
    global sessionDefaultTolerance
    global use720Mode
    global whiteDetectX
    global whiteDetectY
    global choiceImageSize
    global choiceStatusText
    global choiceDefaultText
    global choiceGroups
    global choiceGroupLabels
    global choicePics
    global choiceNames
    global choiceTols
    global choiceTypes
    global detailsText
    global bestPic
    global bestName
    global bestType
    global bestTolerance
    global bestReason
    global banishPic
    global banishName
    global banishType
    global banishTolerance
    global banishedLifeText
    global lifeActionText

    choiceGui := Gui("+AlwaysOnTop +Border", "Choices")
    SetGuiBaseTheme(choiceGui)
    choiceGui.SetFont(ThemeFontOptions(use720Mode ? "s6" : "s7"), "Segoe UI")

    choiceImageSize := GS(42)
    choiceGroups := []
    choiceGroupLabels := []
    choicePics := []
    choiceNames := []
    choiceTols := []
    choiceTypes := []

    choiceStatusText := choiceGui.AddText(
        "x" GS(8) " y" GS(5) " w" GS(384) " Center",
        "Waiting for white at " whiteDetectX ", " whiteDetectY "..."
    )
    choiceDefaultText := choiceGui.AddText(
        "x" GS(8) " y" GS(17) " w" GS(384) " Center",
        "Base Tolerance: *" sessionDefaultTolerance
    )

    Loop 5 {
        slot := A_Index
        groupX := 8 + ((slot - 1) * 76)
        group := choiceGui.AddGroupBox(
            "x" GS(groupX) " y" GS(30) " w" GS(70) " h" GS(90),
            ""
        )

        groupLabel := choiceGui.AddText(
            "x" GS(groupX + 4) " y" GS(30) " w" GS(62) " Center",
            "Choice " slot
        )

        pic := choiceGui.AddPicture(
            "x" GS(groupX + 14) " y" GS(42) " w" choiceImageSize " h" choiceImageSize
        )
        nameControl := choiceGui.AddText(
            "x" GS(groupX + 3) " y" GS(85) " w" GS(64) " Center",
            "Waiting..."
        )
        tolControl := choiceGui.AddText(
            "x" GS(groupX + 3) " y" GS(98) " w" GS(64) " Center",
            "Tol: ?"
        )
        typeControl := choiceGui.AddText(
            "x" GS(groupX + 3) " y" GS(109) " w" GS(64) " Center",
            ""
        )
        choiceGroups.Push(group)
        choiceGroupLabels.Push(groupLabel)
        choicePics.Push(pic)
        choiceNames.Push(nameControl)
        choiceTols.Push(tolControl)
        choiceTypes.Push(typeControl)
    }

    detailsText := choiceGui.AddEdit(
        "x" GS(8) " y" GS(125) " w" GS(384) " h" GS(34) " ReadOnly -Wrap",
        ""
    )

    choiceGui.AddGroupBox(
        "x" GS(8) " y" GS(164) " w" GS(188) " h" GS(64),
        ""
    )

    choiceGui.AddText(
        "x" GS(45) " y" GS(164) " w" GS(114) " Center",
        "Best Choice"
    )
    bestPic := choiceGui.AddPicture(
        "x" GS(16) " y" GS(178) " w" GS(32) " h" GS(32)
    )
    bestName := choiceGui.AddText(
        "x" GS(54) " y" GS(174) " w" GS(136), "Waiting..."
    )
    bestType := choiceGui.AddText(
        "x" GS(54) " y" GS(188) " w" GS(136), "Type: ?"
    )
    bestTolerance := choiceGui.AddText(
        "x" GS(54) " y" GS(201) " w" GS(136), "Tolerance: ?"
    )
    bestReason := choiceGui.AddText(
        "x" GS(16) " y" GS(214) " w" GS(174) " Center", ""
    )

    choiceGui.AddGroupBox(
        "x" GS(204) " y" GS(164) " w" GS(188) " h" GS(64),
        ""
    )

    choiceGui.AddText(
        "x" GS(255) " y" GS(164) " w" GS(86) " Center",
        "Banish"
    )
    banishPic := choiceGui.AddPicture(
        "x" GS(212) " y" GS(178) " w" GS(32) " h" GS(32)
    )
    banishName := choiceGui.AddText(
        "x" GS(250) " y" GS(174) " w" GS(136), "None"
    )
    banishType := choiceGui.AddText(
        "x" GS(250) " y" GS(188) " w" GS(136), ""
    )
    banishTolerance := choiceGui.AddText(
        "x" GS(250) " y" GS(201) " w" GS(136), ""
    )

    banishedLifeText := choiceGui.AddText(
        "x" GS(8) " y" GS(234) " w" GS(384) " Center",
        "Banished this life: None"
    )
    lifeActionText := choiceGui.AddText(
        "x" GS(8) " y" GS(252) " w" GS(384) " Center",
        "Rerolls left: 0 | Banishes left: 0"
    )

    ApplyThemeToGui(choiceGui)
    UpdateLifeActionDisplay()
    choiceGui.Show(
        "x" choiceGuiX " y" choiceGuiY " w" GS(choiceGuiWidthBase) " h" GS(278) " Hide"
    )

    PositionChoiceGuiTopRight()
}


PositionChoiceGuiTopRight() {

    global choiceGui
    global choiceGuiX
    global choiceGuiY

    if !IsObject(choiceGui)
        return

    oldDetectHidden := A_DetectHiddenWindows
    DetectHiddenWindows true

    try {

        WinGetPos(
            &currentX,
            &currentY,
            &windowWidth,
            &windowHeight,
            "ahk_id " choiceGui.Hwnd
        )

        choiceGuiX := A_ScreenWidth - windowWidth
        choiceGuiY := 0

        WinMove(
            choiceGuiX,
            choiceGuiY,
            ,
            ,
            "ahk_id " choiceGui.Hwnd
        )
    }
    finally {
        DetectHiddenWindows oldDetectHidden
    }
}


SetChoiceSlotCount(choiceCount) {

    global choiceGroups
    global choiceGroupLabels
    global choicePics
    global choiceNames
    global choiceTols
    global choiceTypes

    if choiceCount < 1 || choiceCount > 5
        choiceCount := 5

    Loop 5 {

        slot := A_Index
        visible := slot <= choiceCount

        choiceGroups[slot].Visible := visible
        choiceGroupLabels[slot].Visible := visible
        choicePics[slot].Visible := visible
        choiceNames[slot].Visible := visible
        choiceTols[slot].Visible := visible
        choiceTypes[slot].Visible := visible
    }
}

UpdateToleranceDisplays() {

    global sessionDefaultTolerance
    global toleranceText
    global choiceDefaultText

    toleranceText.Text := "Base Tolerance: *" sessionDefaultTolerance

    if IsSet(choiceDefaultText)
        choiceDefaultText.Text := "Base Tolerance: *" sessionDefaultTolerance
}

ResetChoiceGui(status := "") {

    global choiceStatusText
    global whiteDetectX
    global whiteDetectY
    global choicePics
    global choiceNames
    global choiceTols
    global choiceTypes
    global detailsText
    global bestPic
    global bestName
    global bestType
    global bestTolerance
    global bestReason

    if status = ""
        status := "Waiting for white at " whiteDetectX ", " whiteDetectY "..."

    UpdateToleranceDisplays()
    if IsObject(choiceStatusText)
        choiceStatusText.Text := status

    Loop 5 {
        slot := A_Index
        choicePics[slot].Value := ""
        choiceNames[slot].Text := "Waiting..."
        choiceTols[slot].Text := "Tolerance: ?"
        choiceTypes[slot].Text := ""
    }

    if IsObject(detailsText)
        detailsText.Value := ""
    if IsObject(bestPic)
        bestPic.Value := ""
    if IsObject(bestName)
        bestName.Text := "Waiting..."
    if IsObject(bestType)
        bestType.Text := "Type: ?"
    if IsObject(bestTolerance)
        bestTolerance.Text := "Tolerance: ?"
    if IsObject(bestReason)
        bestReason.Text := ""

    ClearBanishChoice()
    UpdateLifeActionDisplay()
}

UpdateChoiceSlot(slot, result) {

    global choiceImageSize
    global choicePics
    global choiceNames
    global choiceTols
    global choiceTypes

    if slot < 1 || slot > 5
        return

    name := result["Name"]
    tolerance := result["Tolerance"]
    type := result["Type"]
    imagePath := result["Path"]

    choicePics[slot].Value :=
        "*w" choiceImageSize
        . " *h" choiceImageSize
        . " "
        . imagePath

    choiceNames[slot].Text := name
    choiceTols[slot].Text := "Tolerance: *" tolerance
    choiceTypes[slot].Text := type
}

UpdateBestChoice(result) {

    global bestPic
    global bestName
    global bestType
    global bestTolerance
    global bestReason
    global weaponRemaining
    global upgradeRemaining

    bestPic.Value := "*w" GS(32) " *h" GS(32) " " result["Path"]
    bestName.Text := result["Name"]
    bestType.Text := "Type: " result["Type"]
    bestTolerance.Text := "Tolerance: *" result["Tolerance"]

    if result["Type"] = "Weapon" {
        remaining := weaponRemaining.Get(result["Name"], 5)
        bestReason.Text := "Remaining: " remaining
    }
    else {
        remaining := upgradeRemaining.Get(result["Name"], 10)
        bestReason.Text := "Remaining: " remaining
    }
}



UpdateBanishChoice(result) {
    global banishPic
    global banishName
    global banishType
    global banishTolerance
    if !IsObject(result) {
        ClearBanishChoice()
        return
    }
    if IsObject(banishPic)
        banishPic.Value := "*w" GS(32) " *h" GS(32) " " result["Path"]
    if IsObject(banishName)
        banishName.Text := result["Name"]
    if IsObject(banishType)
        banishType.Text := "Will banish"
    if IsObject(banishTolerance)
        banishTolerance.Text := "Tolerance: *" result["Tolerance"]
}

ClearBanishChoice(message := "None") {
    global banishPic
    global banishName
    global banishType
    global banishTolerance
    if IsObject(banishPic)
        banishPic.Value := ""
    if IsObject(banishName)
        banishName.Text := message
    if IsObject(banishType)
        banishType.Text := ""
    if IsObject(banishTolerance)
        banishTolerance.Text := ""
}

FormatBanishedThisLife() {
    global banishedThisLife
    if !IsObject(banishedThisLife) || banishedThisLife.Length = 0
        return "None"
    output := ""
    for index, name in banishedThisLife {
        if index > 1
            output .= ", "
        output .= name
    }
    return output
}

UpdateLifeActionDisplay() {
    global rerollsLeft
    global banishesLeft
    global banishedLifeText
    global lifeActionText
    if IsObject(banishedLifeText)
        banishedLifeText.Text := "Banished this life: " FormatBanishedThisLife()
    if IsObject(lifeActionText)
        lifeActionText.Text := "Rerolls left: " rerollsLeft " | Banishes left: " banishesLeft
}

ResetLifeActionCounts() {
    global rerollsPerLife
    global banishesPerLife
    global rerollsLeft
    global banishesLeft
    global banishedThisLife
    rerollsLeft := rerollsPerLife
    banishesLeft := banishesPerLife
    banishedThisLife := []
    UpdateLifeActionDisplay()
}

GetPriorityArrayForRarity(rarity) {
    global commonUpgrades
    global rareUpgrades
    global epicUpgrades
    global legendaryUpgrades
    switch rarity {
        case "common":
            return commonUpgrades
        case "rare":
            return rareUpgrades
        case "epic":
            return epicUpgrades
        case "legendary":
            return legendaryUpgrades
    }
    return []
}

GetBanishCandidate(foundSlots, rarity) {
    global BANISH_MARKER
    global banishesLeft
    if banishesLeft <= 0
        return 0
    priorityArray := GetPriorityArrayForRarity(rarity)
    belowBanish := false
    for name in priorityArray {
        if name = BANISH_MARKER {
            belowBanish := true
            continue
        }
        if !belowBanish
            continue
        for slot, result in foundSlots {
            if result["Name"] = name
                return result
        }
    }
    return 0
}

IsRerollEnabledForRarity(rarity) {
    global rerollCommonEnabled
    global rerollRareEnabled
    global rerollEpicEnabled
    global rerollLegendaryEnabled
    switch rarity {
        case "common":
            return rerollCommonEnabled
        case "rare":
            return rerollRareEnabled
        case "epic":
            return rerollEpicEnabled
        case "legendary":
            return rerollLegendaryEnabled
    }
    return false
}

PerformReroll(rarity) {
    global rerollsLeft
    global whiteRestX
    global whiteRestY
    global choiceStatusText

    if rerollsLeft <= 0
        return false

    CheckCloseNow()
    if ShouldAbortCurrentActionForResume()
        return false

    rerollX := ScaleX(1110)
    rerollY := ScaleY(985)
    if IsObject(choiceStatusText)
        choiceStatusText.Text := "Rerolling " rarity " | rerolls left: " rerollsLeft

    MouseMove rerollX, rerollY, 2
    Sleep 100
    CheckCloseNow()
    if ShouldAbortCurrentActionForResume()
        return false

    Click
    rerollsLeft -= 1
    UpdateLifeActionDisplay()
    Sleep 150
    MouseMove whiteRestX, whiteRestY, 2
    return true
}

PerformBanishChoice(result) {
    global banishesLeft
    global banishedThisLife
    global whiteRestX
    global whiteRestY
    global choiceStatusText

    if !IsObject(result) || banishesLeft <= 0
        return false

    CheckCloseNow()
    if ShouldAbortCurrentActionForResume()
        return false

    banishButtonX := ScaleX(810)
    banishButtonY := ScaleY(985)
    targetX := result["X"] + ScaleX(70)
    targetY := result["Y"] + ScaleY(70)
    UpdateBanishChoice(result)
    if IsObject(choiceStatusText)
        choiceStatusText.Text := "Banishing " result["Name"] "..."

    MouseMove banishButtonX, banishButtonY, 2
    Sleep 100
    CheckCloseNow()
    if ShouldAbortCurrentActionForResume()
        return false
    Click

    Sleep 100
    CheckCloseNow()
    if ShouldAbortCurrentActionForResume()
        return false
    MouseMove targetX, targetY, 2
    Click

    banishesLeft -= 1
    banishedThisLife.Push(result["Name"])
    UpdateLifeActionDisplay()
    Sleep 250
    MouseMove whiteRestX, whiteRestY, 2
    Sleep 100
    return true
}

ShouldRerollWeaponChoices(foundSlots) {

    global weaponPriority
    global weaponRemaining
    global WEAPON_REROLL_MARKER

    wantedWeapons := Map()

    for weapon in weaponPriority {
        if weapon = WEAPON_REROLL_MARKER
            break

        wantedWeapons[weapon] := true
    }

    foundSelectableWanted := false
    foundSelectableAny := false

    for slot, result in foundSlots {
        if result["Type"] != "Weapon"
            continue

        if weaponRemaining.Get(result["Name"], 5) <= 0
            continue

        foundSelectableAny := true

        if wantedWeapons.Has(result["Name"]) {
            foundSelectableWanted := true
            break
        }
    }

    if !foundSelectableAny
        return false

    return !foundSelectableWanted
}

GetBestChoice(foundSlots) {

    global weaponPriority
    global commonUpgrades
    global rareUpgrades
    global epicUpgrades
    global legendaryUpgrades
    global weaponRemaining
    global upgradeRemaining

    for weapon in weaponPriority {
        for slot, result in foundSlots {
            if (
                result["Type"] = "Weapon"
                && result["Name"] = weapon
                && weaponRemaining.Get(weapon, 5) > 0
            )
                return result
        }
    }

    for upgrade in commonUpgrades {
        for slot, result in foundSlots {
            if (
                result["Type"] = "Common Upgrade"
                && result["Name"] = upgrade
                && upgradeRemaining.Get(upgrade, 10) > 0
            )
                return result
        }
    }

    for upgrade in rareUpgrades {
        for slot, result in foundSlots {
            if (
                result["Type"] = "Rare Upgrade"
                && result["Name"] = upgrade
                && upgradeRemaining.Get(upgrade, 10) > 0
            )
                return result
        }
    }

    for upgrade in epicUpgrades {
        for slot, result in foundSlots {
            if (
                result["Type"] = "Epic Upgrade"
                && result["Name"] = upgrade
                && upgradeRemaining.Get(upgrade, 10) > 0
            )
                return result
        }
    }

    for upgrade in legendaryUpgrades {
        for slot, result in foundSlots {
            if (
                result["Type"] = "Legendary Upgrade"
                && result["Name"] = upgrade
                && upgradeRemaining.Get(upgrade, 10) > 0
            )
                return result
        }
    }

    return 0
}

ColorNear(sampleColor, targetColor, tolerance := 8) {

    sampleColor := sampleColor & 0xFFFFFF
    targetColor := targetColor & 0xFFFFFF

    sampleR := (sampleColor >> 16) & 0xFF
    sampleG := (sampleColor >> 8) & 0xFF
    sampleB := sampleColor & 0xFF

    targetR := (targetColor >> 16) & 0xFF
    targetG := (targetColor >> 8) & 0xFF
    targetB := targetColor & 0xFF

    return (
        Abs(sampleR - targetR) <= tolerance
        && Abs(sampleG - targetG) <= tolerance
        && Abs(sampleB - targetB) <= tolerance
    )
}

GetKnownRarityFromColor(color) {

    global commonRarityColor
    global rareRarityColor
    global epicRarityColor
    global legendaryRarityColor
    global mythicRarityColor
    global limitedRarityColor

    if ColorNear(color, Integer(commonRarityColor))
        return "common"
    if ColorNear(color, Integer(rareRarityColor))
        return "rare"
    if ColorNear(color, Integer(epicRarityColor))
        return "epic"
    if ColorNear(color, Integer(legendaryRarityColor))
        return "legendary"
    if ColorNear(color, Integer(mythicRarityColor))
        return "mythic"
    if ColorNear(color, Integer(limitedRarityColor))
        return "limited"

    return ""
}

GetChoiceLayoutCoordinates(choiceCount) {

    switch choiceCount {
        case 5:
            return [
                [290, 355],
                [625, 355],
                [960, 355],
                [1295, 355],
                [1630, 355]
            ]
        case 4:
            return [
                [455, 355],
                [790, 355],
                [1125, 355],
                [1460, 355]
            ]
        case 3:
            return [
                [625, 355],
                [960, 355],
                [1295, 355]
            ]
        case 2:
            ; Post-banish centered pair, keeping the same 335px spacing.
            return [
                [790, 355],
                [1125, 355]
            ]
        case 1:
            return [
                [960, 355]
            ]
    }

    return []
}

SampleChoiceLayoutColors(choiceCount, pointGrid := 0) {

    if !IsObject(pointGrid)
        pointGrid := SampleAllChoiceRarityPoints()

    coords := GetChoiceLayoutCoordinates(choiceCount)
    colors := []
    labels := []
    matchedCount := 0

    for coord in coords {

        point := pointGrid[coord[1]]
        sampleColor := point["Color"]
        rarity := point["Label"]

        colors.Push(sampleColor)
        labels.Push(rarity)

        if rarity != ""
            matchedCount += 1
    }

    return Map(
        "Count", choiceCount,
        "Colors", colors,
        "Labels", labels,
        "Matched", matchedCount
    )
}


SampleChoiceRarityPoint(baseX, baseY) {

    centerColor := PixelGetColor(
        ScaleX(baseX),
        ScaleY(baseY),
        "RGB"
    ) & 0xFFFFFF

    centerLabel := GetKnownRarityFromColor(centerColor)

    ; Fast path: a recognized center pixel is normally enough.
    ; The second full layout read still verifies stability.
    if centerLabel != "" {
        return Map(
            "Color", centerColor,
            "Label", centerLabel,
            "Votes", 1
        )
    }

    ; Only spend extra PixelGetColor calls when the exact center is "?".
    offsets := [
        [-3, 0],
        [3, 0],
        [0, -3],
        [0, 3]
    ]

    counts := Map()
    representativeColors := Map()

    for offset in offsets {

        sampleColor := PixelGetColor(
            ScaleX(baseX + offset[1]),
            ScaleY(baseY + offset[2]),
            "RGB"
        ) & 0xFFFFFF

        rarity := GetKnownRarityFromColor(sampleColor)

        if rarity = ""
            continue

        counts[rarity] := counts.Get(rarity, 0) + 1

        if !representativeColors.Has(rarity)
            representativeColors[rarity] := sampleColor
    }

    bestLabel := ""
    bestCount := 0

    for rarity, count in counts {
        if count > bestCount {
            bestLabel := rarity
            bestCount := count
        }
    }

    if bestLabel = "" {
        return Map(
            "Color", centerColor,
            "Label", "",
            "Votes", 0
        )
    }

    return Map(
        "Color", representativeColors.Get(bestLabel, centerColor),
        "Label", bestLabel,
        "Votes", bestCount
    )
}


SampleAllChoiceRarityPoints() {
    grid := Map()

    for baseX in [290, 455, 625, 790, 960, 1125, 1295, 1460, 1630] {
        CheckCloseNow()
        grid[baseX] := SampleChoiceRarityPoint(baseX, 355)
    }

    return grid
}


ChoiceLabelsContainUnknown(labels) {

    for rarity in labels {
        if rarity = ""
            return true
    }

    return false
}


ProbeHasKnownAtEither(firstProbe, secondProbe, index) {

    return (
        firstProbe["Labels"][index] != ""
        || secondProbe["Labels"][index] != ""
    )
}


MakeChoiceRescanInfo(reason, probe := 0) {

    labels := []
    colors := []

    if IsObject(probe) {
        labels := probe["Labels"]
        colors := probe["Colors"]
    }

    return Map(
        "Count", IsObject(probe) ? probe["Count"] : 0,
        "Mode", "unknown",
        "Rarity", "",
        "Labels", labels,
        "Colors", colors,
        "Reason", reason,
        "NeedsRescan", true
    )
}

GetUniqueDetectedRarities(labels) {

    unique := []

    for rarity in labels {

        if rarity = ""
            continue

        exists := false

        for existing in unique {
            if existing = rarity {
                exists := true
                break
            }
        }

        if !exists
            unique.Push(rarity)
    }

    return unique
}

GetStableProbeMatchCount(firstProbe, secondProbe) {

    stableCount := 0

    Loop firstProbe["Count"] {

        index := A_Index
        firstLabel := firstProbe["Labels"][index]
        secondLabel := secondProbe["Labels"][index]

        if (
            firstLabel != ""
            && firstLabel = secondLabel
        )
            stableCount += 1
    }

    return stableCount
}

IsStableKnownProbeSlot(firstProbe, secondProbe, index) {

    firstLabel := firstProbe["Labels"][index]
    secondLabel := secondProbe["Labels"][index]

    return (
        firstLabel != ""
        && firstLabel = secondLabel
    )
}

IsStableRarityGridPoint(firstGrid, secondGrid, baseX) {

    firstLabel := firstGrid[baseX]["Label"]
    secondLabel := secondGrid[baseX]["Label"]

    return (
        firstLabel != ""
        && firstLabel = secondLabel
    )
}


GetStableLayoutPointCount(choiceCount, firstGrid, secondGrid) {

    stableCount := 0

    for coord in GetChoiceLayoutCoordinates(choiceCount) {
        if IsStableRarityGridPoint(firstGrid, secondGrid, coord[1])
            stableCount += 1
    }

    return stableCount
}


HasRarityEvidenceAtX(firstGrid, secondGrid, baseX) {

    return (
        firstGrid[baseX]["Label"] != ""
        || secondGrid[baseX]["Label"] != ""
    )
}


VerifySmallerLayoutIsNotStillExpanding(choiceCount) {

    ; 5 and 4 are already fully distinguishable from the unified map.
    ; Only small layouts need a tiny extra check against a larger layout
    ; that might still be finishing its animation.
    verifyXs := []

    switch choiceCount {
        case 3:
            verifyXs := [290, 1630]
        case 2:
            verifyXs := [455, 1460]
        case 1:
            verifyXs := [625, 1295, 290, 1630]
        default:
            return true
    }

    Sleep 60

    for baseX in verifyXs {
        if SampleChoiceRarityPoint(baseX, 355)["Label"] != ""
            return false
    }

    return true
}

DetectChoiceLayoutAndType() {

    lastInfo := 0

    ; Normal screens should resolve on the first unified pass.
    ; Retry only when a point is unstable / question-marked.
    Loop 3 {

        info := DetectChoiceLayoutAndTypeOnce()
        lastInfo := info

        if !info["NeedsRescan"]
            return info

        if A_Index < 3
            Sleep 50
    }

    return lastInfo
}



GetStableRarityAtX(firstGrid, secondGrid, baseX) {

    firstLabel := firstGrid[baseX]["Label"]
    secondLabel := secondGrid[baseX]["Label"]

    if (
        firstLabel != ""
        && firstLabel = secondLabel
    )
        return firstLabel

    return ""
}


BuildStableChoiceProbe(choiceCount, firstGrid, secondGrid) {

    colors := []
    labels := []
    matchedCount := 0

    for coord in GetChoiceLayoutCoordinates(choiceCount) {

        baseX := coord[1]
        rarity := GetStableRarityAtX(
            firstGrid,
            secondGrid,
            baseX
        )

        labels.Push(rarity)

        if rarity != "" {
            matchedCount += 1
            colors.Push(secondGrid[baseX]["Color"])
        }
        else {
            colors.Push(secondGrid[baseX]["Color"])
        }
    }

    return Map(
        "Count", choiceCount,
        "Colors", colors,
        "Labels", labels,
        "Matched", matchedCount
    )
}

GetMajorityRarityAtX(grids, baseX) {

    counts := Map()
    representativeColor := 0

    for grid in grids {

        rarity := grid[baseX]["Label"]

        if rarity = ""
            continue

        counts[rarity] := counts.Get(rarity, 0) + 1

        if representativeColor = 0
            representativeColor := grid[baseX]["Color"]
    }

    bestLabel := ""
    bestCount := 0

    for rarity, count in counts {
        if count > bestCount {
            bestLabel := rarity
            bestCount := count
        }
    }

    ; Two matching reads out of three is enough. A single bad/? read
    ; no longer destroys an otherwise stable 5-choice layout.
    if bestCount >= 2 {
        return Map(
            "Label", bestLabel,
            "Color", representativeColor,
            "Votes", bestCount
        )
    }

    return Map(
        "Label", "",
        "Color", representativeColor,
        "Votes", bestCount
    )
}


HasAnyRarityEvidenceAtX(grids, baseX) {

    for grid in grids {
        if grid[baseX]["Label"] != ""
            return true
    }

    return false
}


SampleChoiceRarityPointWide(baseX, baseY) {

    ; Used only when the normal center/+3px probe could not read a rarity.
    ; A wider local pattern fixes persistent "?" results caused by the
    ; exact probe landing on an edge/shine/animation pixel.
    offsets := [
        [0, 0],
        [-3, 0], [3, 0], [0, -3], [0, 3],
        [-6, 0], [6, 0], [0, -6], [0, 6],
        [-4, -4], [4, -4], [-4, 4], [4, 4],
        [-9, 0], [9, 0], [0, -9], [0, 9]
    ]

    counts := Map()
    representativeColors := Map()

    for offset in offsets {

        CheckCloseNow()

        sampleColor := PixelGetColor(
            ScaleX(baseX + offset[1]),
            ScaleY(baseY + offset[2]),
            "RGB"
        ) & 0xFFFFFF

        rarity := GetKnownRarityFromColor(sampleColor)

        if rarity = ""
            continue

        counts[rarity] := counts.Get(rarity, 0) + 1

        if !representativeColors.Has(rarity)
            representativeColors[rarity] := sampleColor
    }

    bestLabel := ""
    bestCount := 0

    for rarity, count in counts {
        if count > bestCount {
            bestLabel := rarity
            bestCount := count
        }
    }

    return Map(
        "Label", bestLabel,
        "Color", bestLabel != ""
            ? representativeColors[bestLabel]
            : 0,
        "Votes", bestCount
    )
}

ResolveRarityPointQuick(baseX) {

    ; Three short wide probes. Two frames agreeing is enough.
    samples := []

    Loop 3 {

        CheckCloseNow()

        samples.Push(
            SampleChoiceRarityPointWide(
                baseX,
                355
            )
        )

        if A_Index < 3
            Sleep 25
    }

    counts := Map()
    representativeColors := Map()

    for sample in samples {

        rarity := sample["Label"]

        if rarity = ""
            continue

        counts[rarity] := counts.Get(rarity, 0) + 1

        if !representativeColors.Has(rarity)
            representativeColors[rarity] := sample["Color"]
    }

    bestLabel := ""
    bestCount := 0

    for rarity, count in counts {
        if count > bestCount {
            bestLabel := rarity
            bestCount := count
        }
    }

    if bestCount >= 2 {
        return Map(
            "Label", bestLabel,
            "Color", representativeColors.Get(bestLabel, 0),
            "Votes", bestCount
        )
    }

    return Map(
        "Label", "",
        "Color", 0,
        "Votes", bestCount
    )
}


BuildMajorityChoiceProbe(choiceCount, grids) {

    labels := []
    colors := []
    matchedCount := 0

    for coord in GetChoiceLayoutCoordinates(choiceCount) {

        baseX := coord[1]
        result := GetMajorityRarityAtX(grids, baseX)

        ; If this expected card was the one unclear coordinate, rescan
        ; ONLY that coordinate quickly before giving up on the screen.
        if result["Label"] = ""
            result := ResolveRarityPointQuick(baseX)

        labels.Push(result["Label"])
        colors.Push(result["Color"])

        if result["Label"] != ""
            matchedCount += 1
    }

    return Map(
        "Count", choiceCount,
        "Labels", labels,
        "Colors", colors,
        "Matched", matchedCount
    )
}


ResolveUniqueLayoutEvidence(grids, xList) {

    ; Fast majority from the three unified sweeps.
    for baseX in xList {
        if GetMajorityRarityAtX(grids, baseX)["Label"] != ""
            return true
    }

    sawUnstableEvidence := false

    ; If either unique point showed any rarity evidence, use the wider
    ; targeted recovery on ALL such points before declaring it unstable.
    for baseX in xList {

        if !HasAnyRarityEvidenceAtX(grids, baseX)
            continue

        recovered := ResolveRarityPointQuick(baseX)

        if recovered["Label"] != ""
            return true

        sawUnstableEvidence := true
    }

    return sawUnstableEvidence ? "unstable" : false
}

CountUnknownRarityLabels(labels) {
    count := 0
    for rarity in labels {
        if rarity = ""
            count += 1
    }
    return count
}

CountKnownRarityLabels(labels) {
    count := 0
    for rarity in labels {
        if rarity != ""
            count += 1
    }
    return count
}

CanProceedWithPartialRarity(choiceCount, labels) {

    if choiceCount < 4
        return false

    knownCount := CountKnownRarityLabels(labels)
    unknownCount := CountUnknownRarityLabels(labels)

    if unknownCount < 1 || knownCount < 1
        return false

    uniqueRarities := GetUniqueDetectedRarities(labels)

    ; Any readable Mythic/Limited card already proves a weapon screen.
    for rarity in uniqueRarities {
        if rarity = "mythic" || rarity = "limited"
            return true
    }

    ; Two different readable rarities prove a mixed weapon screen,
    ; even if one or more other rarity probes are unreadable.
    if uniqueRarities.Length > 1 && knownCount >= 2
        return true

    ; If all readable cards agree, require at least three independent
    ; readable cards. The screen can then continue as a same-color
    ; candidate, and ImageSearch decides upgrade vs weapon.
    if uniqueRarities.Length = 1 && knownCount >= 3
        return true

    return false
}

DetectChoiceLayoutAndTypeOnce() {

    ; Three complete sweeps of the same nine coordinates.
    ; This is still cheap (only PixelGetColor), and majority voting is
    ; much more reliable than requiring two perfect identical frames.
    grids := []

    Loop 3 {

        CheckCloseNow()
        grids.Push(SampleAllChoiceRarityPoints())

        if A_Index < 3
            Sleep 35
    }

    chosenCount := 0
    detectionNote := ""

    ; ========================================================
    ; COUNT FROM UNIQUE COORDINATES, LARGEST FIRST
    ; ========================================================

    evidence5 := ResolveUniqueLayoutEvidence(
        grids,
        [290, 1630]
    )

    if evidence5 = true {

        chosenCount := 5
        detectionNote := "5-choice unique outer majority confirmed."

    }
    else if evidence5 = "unstable" {

        return MakeChoiceRescanInfo(
            "Unstable 5-choice outer coordinate; rescanning."
        )

    }
    else {

        evidence4 := ResolveUniqueLayoutEvidence(
            grids,
            [455, 1460]
        )

        if evidence4 = true {

            chosenCount := 4
            detectionNote := "4-choice unique outer majority confirmed."

        }
        else if evidence4 = "unstable" {

            return MakeChoiceRescanInfo(
                "Unstable 4-choice outer coordinate; rescanning."
            )

        }
        else {

            evidence3 := ResolveUniqueLayoutEvidence(
                grids,
                [625, 1295]
            )

            if evidence3 = true {

                chosenCount := 3
                detectionNote := "3-choice outer majority confirmed."

            }
            else if evidence3 = "unstable" {

                return MakeChoiceRescanInfo(
                    "Unstable 3-choice outer coordinate; rescanning."
                )

            }
            else {

                evidence2 := ResolveUniqueLayoutEvidence(
                    grids,
                    [790, 1125]
                )

                if evidence2 = true {

                    chosenCount := 2
                    detectionNote := "2-choice majority confirmed."

                }
                else if evidence2 = "unstable" {

                    return MakeChoiceRescanInfo(
                        "Unstable 2-choice coordinate; rescanning."
                    )

                }
                else {

                    center := GetMajorityRarityAtX(
                        grids,
                        960
                    )

                    if center["Label"] = ""
                        center := ResolveRarityPointQuick(960)

                    if center["Label"] != "" {

                        chosenCount := 1
                        detectionNote := "Single center majority confirmed."

                    }
                    else {

                        return MakeChoiceRescanInfo(
                            "No stable rarity layout found; rescanning."
                        )
                    }
                }
            }
        }
    }

    ; ========================================================
    ; RARITIES FOR THE CHOSEN COUNT
    ; ========================================================

    chosen := BuildMajorityChoiceProbe(
        chosenCount,
        grids
    )

    partialRarityOk := false

    ; A confirmed 4/5-choice layout no longer gets trapped just because
    ; one rarity pixel remains "?". Do NOT invent the missing rarity.
    ; Instead, use only the readable rarity evidence to decide whether it
    ; is already enough to classify safely, then let ImageSearch identify
    ; the actual selectable cards.
    if ChoiceLabelsContainUnknown(chosen["Labels"]) {

        if !CanProceedWithPartialRarity(
            chosenCount,
            chosen["Labels"]
        ) {
            return MakeChoiceRescanInfo(
                "Question mark remained in "
                . chosenCount
                . "-choice layout without enough readable evidence; rescanning.",
                chosen
            )
        }

        partialRarityOk := true
        detectionNote .= " Partial rarity read accepted; image matching will verify cards."
    }

    uniqueRarities := GetUniqueDetectedRarities(chosen["Labels"])

    mode := "unknown"
    rarity := ""
    reason := detectionNote

    if uniqueRarities.Length > 1 {

        mode := "weapon"
        reason .= " Mixed rarities confirm weapon screen."

    }
    else if uniqueRarities.Length = 1 {

        rarity := uniqueRarities[1]

        if rarity = "mythic" || rarity = "limited" {

            mode := "weapon"
            reason .= " Mythic/Limited confirms weapon screen."

        }
        else {

            mode := "same_color_candidate"
            reason .= " Same-color screen requires image type confirmation."
        }
    }

    if mode = "unknown" {
        return MakeChoiceRescanInfo(
            "Rarity/type classification incomplete; rescanning.",
            chosen
        )
    }

    return Map(
        "Count", chosenCount,
        "Mode", mode,
        "Rarity", rarity,
        "Labels", chosen["Labels"],
        "Colors", chosen["Colors"],
        "Reason", reason,
        "NeedsRescan", false,
        "PartialRarityOk", partialRarityOk
    )
}

FormatDetectedRarityLabels(labels) {

    output := ""

    for index, rarity in labels {
        if index > 1
            output .= ", "

        output .= rarity = "" ? "?" : rarity
    }

    return output
}

GetUpgradeTypeLabel(rarity) {

    switch rarity {
        case "common":
            return "Common Upgrade"
        case "rare":
            return "Rare Upgrade"
        case "epic":
            return "Epic Upgrade"
        case "legendary":
            return "Legendary Upgrade"
    }

    return "Upgrade"
}

GetUpgradeFolderForRarity(rarity) {

    global upgradeFolder
    return upgradeFolder rarity "\"
}

GetUpgradeListForRarity(rarity) {

    global commonUpgrades
    global rareUpgrades
    global epicUpgrades
    global legendaryUpgrades
    global BANISH_MARKER

    source := []

    switch rarity {
        case "common":
            source := commonUpgrades
        case "rare":
            source := rareUpgrades
        case "epic":
            source := epicUpgrades
        case "legendary":
            source := legendaryUpgrades
        default:
            return []
    }

    searchable := []

    for name in source {
        if name != BANISH_MARKER
            searchable.Push(name)
    }

    return searchable
}


CachedImageFileExists(imagePath) {

    global imageExistenceCache

    if imageExistenceCache.Has(imagePath)
        return imageExistenceCache[imagePath]

    exists := FileExist(imagePath) ? true : false
    imageExistenceCache[imagePath] := exists

    return exists
}


MakeChoiceResult(name, typeLabel, imagePath, tolerance, x, y) {

    return Map(
        "Name", name,
        "Type", typeLabel,
        "Path", imagePath,
        "Tolerance", tolerance,
        "X", x,
        "Y", y
    )
}

GetChoiceSlotSearchBounds(
    choiceCount,
    slot,
    &left,
    &top,
    &right,
    &bottom
) {

    global searchLeft
    global searchTop
    global searchRight
    global searchBottom

    coords := GetChoiceLayoutCoordinates(choiceCount)

    if (
        choiceCount < 2
        || choiceCount > 5
        || slot < 1
        || slot > coords.Length
    ) {
        left := searchLeft
        top := searchTop
        right := searchRight
        bottom := searchBottom
        return
    }

    ; Split the active 2/3/4/5-choice search rectangle at the
    ; midpoint between neighboring 335px-spaced card centers.
    if slot = 1 {
        left := searchLeft
    }
    else {
        previousCenterX := ScaleX(coords[slot - 1][1])
        currentCenterX := ScaleX(coords[slot][1])
        left := Floor((previousCenterX + currentCenterX) / 2) + 1
    }

    if slot = coords.Length {
        right := searchRight
    }
    else {
        currentCenterX := ScaleX(coords[slot][1])
        nextCenterX := ScaleX(coords[slot + 1][1])
        right := Floor((currentCenterX + nextCenterX) / 2)
    }

    top := searchTop
    bottom := searchBottom
}

TryChoiceImageSearchInSlot(
    &foundX,
    &foundY,
    imagePath,
    tolerance,
    expectedCount,
    slot
) {

    global use720Mode
    global native720Images

    GetChoiceSlotSearchBounds(
        expectedCount,
        slot,
        &slotLeft,
        &slotTop,
        &slotRight,
        &slotBottom
    )

    searchSpecs := []

    useNarrowCard := (
        expectedCount = 2
        || (expectedCount = 4 && (slot = 2 || slot = 3))
        || (expectedCount = 5 && (slot = 1 || slot = 5))
    )

    if !use720Mode {

        if useNarrowCard {
            searchSpecs.Push(
                "*w139 *h140 *"
                . tolerance
                . " "
                . imagePath
            )
        }
        else {
            searchSpecs.Push(
                "*w140 *h140 *"
                . tolerance
                . " "
                . imagePath
            )
        }

    }
    else {

        if native720Images {

            searchSpecs.Push(
                "*"
                . tolerance
                . " "
                . imagePath
            )

        }
        else {

            if useNarrowCard {
                searchSpecs.Push(
                    "*w92 *h93 *"
                    . tolerance
                    . " "
                    . imagePath
                )
            }
            else {
                searchSpecs.Push(
                    "*w93 *h93 *"
                    . tolerance
                    . " "
                    . imagePath
                )
            }
        }
    }

    for searchSpec in searchSpecs {

        CheckCloseNow()

        if ImageSearch(
            &tempX,
            &tempY,
            slotLeft,
            slotTop,
            slotRight,
            slotBottom,
            searchSpec
        ) {
            foundX := tempX
            foundY := tempY
            return true
        }
    }

    return false
}

UpdateScanDetails(details, force := false) {

    global detailsText
    global lastDetailsGuiUpdate

    now := A_TickCount

    ; Keep scan-debug repainting light while ImageSearch is active.
    if !force && now - lastDetailsGuiUpdate < 600
        return

    if IsObject(detailsText)
        detailsText.Value := details

    lastDetailsGuiUpdate := now
}

FormatMissingSlots(results, expectedCount) {

    missing := ""

    Loop expectedCount {

        slot := A_Index

        if results.Has(slot)
            continue

        if missing != ""
            missing .= ", "

        missing .= slot
    }

    return missing = "" ? "none" : missing
}

GetChoiceWholeRowSearchSpecs(
    imagePath,
    tolerance,
    expectedCount
) {

    global use720Mode
    global native720Images
    global searchLeft
    global searchTop
    global searchRight
    global searchBottom

    specs := []

    if !use720Mode {

        if expectedCount = 2 {

            ; 2 choices: BOTH cards are 139x140.
            ; No 140x140 search is performed anywhere on this layout.
            specs.Push([
                "*w139 *h140 *" tolerance " " imagePath,
                139,
                ScaleX(710),
                ScaleY(430),
                ScaleX(1210),
                ScaleY(590)
            ])

        }
        else if expectedCount = 4 {

            ; 4 choices:
            ; slot 1 = 140x140 ONLY
            ; slot 2 = 139x140 ONLY
            ; slot 3 = 139x140 ONLY
            ; slot 4 = 140x140 ONLY

            ; Slot 1 only.
            specs.Push([
                "*w140 *h140 *" tolerance " " imagePath,
                140,
                ScaleX(370),
                ScaleY(430),
                ScaleX(622),
                ScaleY(590)
            ])

            ; Middle slots 2/3 only.
            specs.Push([
                "*w139 *h140 *" tolerance " " imagePath,
                139,
                ScaleX(623),
                ScaleY(430),
                ScaleX(1292),
                ScaleY(590)
            ])

            ; Slot 4 only.
            specs.Push([
                "*w140 *h140 *" tolerance " " imagePath,
                140,
                ScaleX(1293),
                ScaleY(430),
                ScaleX(1550),
                ScaleY(590)
            ])

        }
        else if expectedCount = 5 {

            ; 5 choices:
            ; slot 1 = 139x140 ONLY
            ; slot 2 = 140x140 ONLY
            ; slot 3 = 140x140 ONLY
            ; slot 4 = 140x140 ONLY
            ; slot 5 = 139x140 ONLY

            ; Slot 1 only.
            specs.Push([
                "*w139 *h140 *" tolerance " " imagePath,
                139,
                ScaleX(210),
                ScaleY(430),
                ScaleX(457),
                ScaleY(590)
            ])

            ; Middle slots 2/3/4 only.
            specs.Push([
                "*w140 *h140 *" tolerance " " imagePath,
                140,
                ScaleX(458),
                ScaleY(430),
                ScaleX(1462),
                ScaleY(590)
            ])

            ; Slot 5 only.
            specs.Push([
                "*w139 *h140 *" tolerance " " imagePath,
                139,
                ScaleX(1463),
                ScaleY(430),
                ScaleX(1710),
                ScaleY(590)
            ])

        }
        else {

            ; 1 and 3 choice layouts use 140x140 only.
            specs.Push([
                "*w140 *h140 *" tolerance " " imagePath,
                140,
                searchLeft,
                searchTop,
                searchRight,
                searchBottom
            ])
        }
    }
    else if native720Images {

        specs.Push([
            "*" tolerance " " imagePath,
            93,
            searchLeft,
            searchTop,
            searchRight,
            searchBottom
        ])

    }
    else {

        if expectedCount = 2 {

            ; 2 choices: both narrow only.
            specs.Push([
                "*w92 *h93 *" tolerance " " imagePath,
                92,
                ScaleX(710),
                ScaleY(430),
                ScaleX(1210),
                ScaleY(590)
            ])

        }
        else if expectedCount = 4 {

            ; Slot 1 only - wide.
            specs.Push([
                "*w93 *h93 *" tolerance " " imagePath,
                93,
                ScaleX(370),
                ScaleY(430),
                ScaleX(622),
                ScaleY(590)
            ])

            ; Slots 2/3 only - narrow.
            specs.Push([
                "*w92 *h93 *" tolerance " " imagePath,
                92,
                ScaleX(623),
                ScaleY(430),
                ScaleX(1292),
                ScaleY(590)
            ])

            ; Slot 4 only - wide.
            specs.Push([
                "*w93 *h93 *" tolerance " " imagePath,
                93,
                ScaleX(1293),
                ScaleY(430),
                ScaleX(1550),
                ScaleY(590)
            ])

        }
        else if expectedCount = 5 {

            ; Slot 1 only - narrow.
            specs.Push([
                "*w92 *h93 *" tolerance " " imagePath,
                92,
                ScaleX(210),
                ScaleY(430),
                ScaleX(457),
                ScaleY(590)
            ])

            ; Slots 2/3/4 only - wide.
            specs.Push([
                "*w93 *h93 *" tolerance " " imagePath,
                93,
                ScaleX(458),
                ScaleY(430),
                ScaleX(1462),
                ScaleY(590)
            ])

            ; Slot 5 only - narrow.
            specs.Push([
                "*w92 *h93 *" tolerance " " imagePath,
                92,
                ScaleX(1463),
                ScaleY(430),
                ScaleX(1710),
                ScaleY(590)
            ])

        }
        else {

            specs.Push([
                "*w93 *h93 *" tolerance " " imagePath,
                93,
                searchLeft,
                searchTop,
                searchRight,
                searchBottom
            ])
        }
    }

    return specs
}


GetChoiceSlotFromImageX(choiceCount, foundX, imageWidth) {

    coords := GetChoiceLayoutCoordinates(choiceCount)
    imageCenterX := foundX + Round(imageWidth / 2)

    bestSlot := 1
    bestDistance := 0x7FFFFFFF

    for slot, coord in coords {

        distance := Abs(imageCenterX - ScaleX(coord[1]))

        if distance < bestDistance {
            bestDistance := distance
            bestSlot := slot
        }
    }

    return bestSlot
}


TryChoiceImageSearchWholeRow(
    &foundX,
    &foundY,
    &foundSlot,
    imagePath,
    tolerance,
    expectedCount
) {

    global use720Mode

    for searchInfo in GetChoiceWholeRowSearchSpecs(
        imagePath,
        tolerance,
        expectedCount
    ) {

        CheckCloseNow()

        searchSpec := searchInfo[1]
        baseImageWidth := searchInfo[2]
        specLeft := searchInfo[3]
        specTop := searchInfo[4]
        specRight := searchInfo[5]
        specBottom := searchInfo[6]

        if ImageSearch(
            &tempX,
            &tempY,
            specLeft,
            specTop,
            specRight,
            specBottom,
            searchSpec
        ) {

            actualWidth := use720Mode
                ? baseImageWidth
                : ScaleX(baseImageWidth)

            foundX := tempX
            foundY := tempY

            foundSlot := GetChoiceSlotFromImageX(
                expectedCount,
                tempX,
                actualWidth
            )

            return true
        }
    }

    return false
}

TryChoiceImageSearchMissingSlots(
    &foundX,
    &foundY,
    &foundSlot,
    imagePath,
    tolerance,
    expectedCount,
    results
) {

    Loop expectedCount {

        slot := A_Index

        if results.Has(slot)
            continue

        if TryChoiceImageSearchInSlot(
            &tempX,
            &tempY,
            imagePath,
            tolerance,
            expectedCount,
            slot
        ) {

            foundX := tempX
            foundY := tempY
            foundSlot := slot
            return true
        }
    }

    return false
}

SearchNamesIntoPhysicalSlots(
    names,
    typeLabel,
    folderPrefix,
    tolerance,
    results,
    expectedCount := 5
) {

    foundNames := Map()

    for existingSlot, existingResult in results
        foundNames[existingResult["Name"]] := true

    for name in names {

        CheckCloseNow()

        if results.Count >= expectedCount
            break

        if foundNames.Has(name)
            continue

        imagePath := folderPrefix name ".png"

        if !CachedImageFileExists(imagePath)
            continue

        found := TryChoiceImageSearchWholeRow(
            &foundX,
            &foundY,
            &foundSlot,
            imagePath,
            tolerance,
            expectedCount
        )

        if !found
            continue

        ; ImageSearch returns the FIRST match in the rectangle. On a
        ; 5-card row that first match can be a tolerance collision in a
        ; slot we already identified. v25 simply discarded the image at
        ; that point, which could make a real 5-choice card impossible to
        ; find. Search only the missing slots before giving up.
        if results.Has(foundSlot) {

            found := TryChoiceImageSearchMissingSlots(
                &foundX,
                &foundY,
                &foundSlot,
                imagePath,
                tolerance,
                expectedCount,
                results
            )

            if !found
                continue
        }

        results[foundSlot] := MakeChoiceResult(
            name,
            typeLabel,
            imagePath,
            tolerance,
            foundX,
            foundY
        )

        foundNames[name] := true
    }
}

MarkUnmatchedChoiceSlots(results, expectedCount) {

    global choiceNames
    global choiceTols
    global choiceTypes

    Loop expectedCount {

        slot := A_Index

        if results.Has(slot)
            continue

        choiceNames[slot].Text := "Not matched"
        choiceTols[slot].Text := "Tolerance: -"
        choiceTypes[slot].Text := ""
    }
}

PopulateFinalChoiceGui(finalSlots, expectedCount) {

    ; Results are keyed by the actual physical slot now.
    Loop expectedCount {

        slot := A_Index

        if finalSlots.Has(slot)
            UpdateChoiceSlot(slot, finalSlots[slot])
    }

    MarkUnmatchedChoiceSlots(finalSlots, expectedCount)
}

GetSearchableWeaponList() {

    global weaponPriority
    global WEAPON_REROLL_MARKER

    searchable := []

    for weapon in weaponPriority {
        if weapon != WEAPON_REROLL_MARKER
            searchable.Push(weapon)
    }

    return searchable
}


RecoverDuplicateChoiceImages(
    names,
    typeLabel,
    folderPrefix,
    tolerance,
    results,
    expectedCount,
    &details,
    debugLabel
) {

    if results.Count >= expectedCount || results.Count = 0
        return

    matchedNames := []
    seenNames := Map()

    ; Snapshot names first so the results Map can be safely expanded later.
    for existingSlot, existingResult in results {

        name := existingResult["Name"]

        if seenNames.Has(name)
            continue

        seenNames[name] := true
        matchedNames.Push(name)
    }

    recoveredCount := 0

    ; Only revisit names that were already positively matched. This is a
    ; cheap end-of-scan recovery for a legitimate duplicate card offer.
    for name in matchedNames {

        imagePath := folderPrefix name ".png"

        while results.Count < expectedCount {

            CheckCloseNow()

            if !TryChoiceImageSearchMissingSlots(
                &foundX,
                &foundY,
                &foundSlot,
                imagePath,
                tolerance,
                expectedCount,
                results
            )
                break

            results[foundSlot] := MakeChoiceResult(
                name,
                typeLabel,
                imagePath,
                tolerance,
                foundX,
                foundY
            )

            recoveredCount += 1
        }
    }

    if recoveredCount > 0 {
        details .=
            debugLabel
            . " duplicate recovery: +"
            . recoveredCount
            . " card(s).`r`n"

        UpdateScanDetails(details)
    }
}

ContinueChoiceCategoryScan(
    names,
    typeLabel,
    folderPrefix,
    expectedCount,
    startTolerance,
    results,
    &details,
    debugLabel,
    recoveryMode := false
) {

    tolerance := Max(15, startTolerance)

    if recoveryMode {
        toleranceWindow := expectedCount = 5 ? 90 : 75
        deadPassLimit := expectedCount = 5 ? 3 : 2
    }
    else {
        toleranceWindow := expectedCount = 5 ? 60 : 45
        deadPassLimit := expectedCount = 5 ? 2 : 1
    }

    maxTolerance := Min(240, tolerance + toleranceWindow)

    noGrowthAfterMatch := 0
    hadAnyMatch := results.Count > 0

    while (
        results.Count < expectedCount
        && tolerance <= maxTolerance
    ) {

        CheckCloseNow()

        beforeCount := results.Count

        SearchNamesIntoPhysicalSlots(
            names,
            typeLabel,
            folderPrefix,
            tolerance,
            results,
            expectedCount
        )

        afterCount := results.Count

        details .=
            debugLabel
            . " *"
            . tolerance
            . ": "
            . afterCount
            . "/"
            . expectedCount
            . " | missing: "
            . FormatMissingSlots(results, expectedCount)
            . (recoveryMode ? " | recovery" : "")
            . "`r`n"

        UpdateScanDetails(details)

        if afterCount >= expectedCount
            break

        if afterCount > beforeCount {
            hadAnyMatch := true
            noGrowthAfterMatch := 0
        }
        else if hadAnyMatch {
            noGrowthAfterMatch += 1

            if noGrowthAfterMatch >= deadPassLimit
                break
        }

        tolerance += 15
        Sleep 1
    }

    if results.Count < expectedCount && results.Count > 0 {

        duplicateTolerance := Min(
            maxTolerance,
            Max(tolerance, startTolerance)
        )

        RecoverDuplicateChoiceImages(
            names,
            typeLabel,
            folderPrefix,
            duplicateTolerance,
            results,
            expectedCount,
            &details,
            debugLabel
        )
    }

    return results
}


FindAnyChoiceImageMatch(
    names,
    typeLabel,
    folderPrefix,
    expectedCount,
    startTolerance,
    maxExtraTolerance := 45
) {

    tolerance := Max(15, startTolerance)
    maxTolerance := Min(240, tolerance + maxExtraTolerance)

    while tolerance <= maxTolerance {

        for name in names {

            CheckCloseNow()
            imagePath := folderPrefix name ".png"

            if !CachedImageFileExists(imagePath)
                continue

            if TryChoiceImageSearchWholeRow(
                &foundX,
                &foundY,
                &foundSlot,
                imagePath,
                tolerance,
                expectedCount
            ) {

                result := MakeChoiceResult(
                    name,
                    typeLabel,
                    imagePath,
                    tolerance,
                    foundX,
                    foundY
                )

                return Map(
                    "Found", true,
                    "Result", result,
                    "Slot", foundSlot,
                    "Tolerance", tolerance
                )
            }
        }

        tolerance += 15
        Sleep 1
    }

    return Map(
        "Found", false,
        "Tolerance", Min(maxTolerance, tolerance - 15)
    )
}

ClassifySameColorChoiceScreen(
    expectedCount,
    detectedRarity,
    startTolerance,
    &details,
    recoveryMode := false
) {

    global weaponFolder

    upgradeNames := GetUpgradeListForRarity(detectedRarity)
    upgradeTypeLabel := GetUpgradeTypeLabel(detectedRarity)
    upgradeFolderPath := GetUpgradeFolderForRarity(detectedRarity)
    weaponNames := GetSearchableWeaponList()

    upgradeResults := Map()
    weaponResults := Map()

    probeWindow := recoveryMode ? 75 : 45

    upgradeProbe := FindAnyChoiceImageMatch(
        upgradeNames,
        upgradeTypeLabel,
        upgradeFolderPath,
        expectedCount,
        startTolerance,
        probeWindow
    )

    if upgradeProbe["Found"] {

        matchedResult := upgradeProbe["Result"]
        matchedSlot := upgradeProbe["Slot"]
        upgradeResults[matchedSlot] := matchedResult

        details .=
            "Type confirmed by upgrade image: "
            . matchedResult["Name"]
            . " at *"
            . matchedResult["Tolerance"]
            . (recoveryMode ? " (recovery)" : "")
            . "`r`n"

        UpdateScanDetails(details)

        return Map(
            "Mode", "upgrade",
            "UpgradeResults", upgradeResults,
            "WeaponResults", weaponResults,
            "LastTolerance", matchedResult["Tolerance"],
            "UpgradeNames", upgradeNames,
            "UpgradeTypeLabel", upgradeTypeLabel,
            "UpgradeFolderPath", upgradeFolderPath,
            "WeaponNames", weaponNames
        )
    }

    weaponProbe := FindAnyChoiceImageMatch(
        weaponNames,
        "Weapon",
        weaponFolder,
        expectedCount,
        startTolerance,
        probeWindow
    )

    if weaponProbe["Found"] {

        matchedResult := weaponProbe["Result"]
        matchedSlot := weaponProbe["Slot"]
        weaponResults[matchedSlot] := matchedResult

        details .=
            "Type confirmed by weapon image: "
            . matchedResult["Name"]
            . " at *"
            . matchedResult["Tolerance"]
            . (recoveryMode ? " (recovery)" : "")
            . "`r`n"

        UpdateScanDetails(details)

        return Map(
            "Mode", "weapon",
            "UpgradeResults", upgradeResults,
            "WeaponResults", weaponResults,
            "LastTolerance", matchedResult["Tolerance"],
            "UpgradeNames", upgradeNames,
            "UpgradeTypeLabel", upgradeTypeLabel,
            "UpgradeFolderPath", upgradeFolderPath,
            "WeaponNames", weaponNames
        )
    }

    details .=
        "No upgrade or weapon image matched during type probe."
        . (recoveryMode ? " Recovery probe was also exhausted." : "")
        . "`r`n"

    return Map(
        "Mode", "ambiguous",
        "UpgradeResults", upgradeResults,
        "WeaponResults", weaponResults,
        "LastTolerance", Max(
            upgradeProbe["Tolerance"],
            weaponProbe["Tolerance"]
        ),
        "UpgradeNames", upgradeNames,
        "UpgradeTypeLabel", upgradeTypeLabel,
        "UpgradeFolderPath", upgradeFolderPath,
        "WeaponNames", weaponNames
    )
}


GetBestChoiceIgnoringLimits(foundSlots) {

    global weaponPriority
    global commonUpgrades
    global rareUpgrades
    global epicUpgrades
    global legendaryUpgrades

    for weapon in weaponPriority {
        for slot, result in foundSlots {
            if (
                result["Type"] = "Weapon"
                && result["Name"] = weapon
            )
                return result
        }
    }

    for upgrade in commonUpgrades {
        for slot, result in foundSlots {
            if (
                result["Type"] = "Common Upgrade"
                && result["Name"] = upgrade
            )
                return result
        }
    }

    for upgrade in rareUpgrades {
        for slot, result in foundSlots {
            if (
                result["Type"] = "Rare Upgrade"
                && result["Name"] = upgrade
            )
                return result
        }
    }

    for upgrade in epicUpgrades {
        for slot, result in foundSlots {
            if (
                result["Type"] = "Epic Upgrade"
                && result["Name"] = upgrade
            )
                return result
        }
    }

    for upgrade in legendaryUpgrades {
        for slot, result in foundSlots {
            if (
                result["Type"] = "Legendary Upgrade"
                && result["Name"] = upgrade
            )
                return result
        }
    }

    return 0
}

ScanWeaponChoicesByColorCount(
    expectedCount,
    startTolerance,
    &details,
    recoveryMode := false
) {

    global weaponFolder

    weaponResults := Map()
    weaponNames := GetSearchableWeaponList()

    ContinueChoiceCategoryScan(
        weaponNames,
        "Weapon",
        weaponFolder,
        expectedCount,
        startTolerance,
        weaponResults,
        &details,
        "Weapons",
        recoveryMode
    )

    return weaponResults
}


GetHighestToleranceInSlots(slots) {

    highest := 0

    for slot, result in slots {
        if result["Tolerance"] > highest
            highest := result["Tolerance"]
    }

    return highest
}


ScanVisibleChoices(allowReroll := true, allowBanish := true, recoveryMode := false) {

    scanStartedAt := A_TickCount

    global sessionDefaultTolerance
    global weaponFolder
    global choiceStatusText
    global rerollsLeft
    global banishesLeft

    screenInfo := DetectChoiceLayoutAndType()

    expectedCount := screenInfo["Count"]
    detectedMode := screenInfo["Mode"]
    detectedRarity := screenInfo["Rarity"]

    details := ""

    if recoveryMode
        details .= "RECOVERY SCAN ENABLED`r`n"

    details .= "Color layout: " expectedCount " choices`r`n"
    details .= "Colors: "
        . FormatDetectedRarityLabels(screenInfo["Labels"])
        . "`r`n"
    details .= "Classification: "
        . detectedMode
        . (detectedRarity != "" ? " " detectedRarity : "")
        . "`r`n"
    details .= screenInfo["Reason"] . "`r`n`r`n"

    UpdateScanDetails(details, true)

    resultMap := Map()
    resultMap["ExpectedCount"] := expectedCount
    resultMap["DetectedRarity"] := detectedRarity

    partialRarityOk := (
        screenInfo.Has("PartialRarityOk")
        && screenInfo["PartialRarityOk"]
    )

    ; The detector is the authority on whether a partial rarity read has
    ; enough evidence. Unknown labels are allowed ONLY when it explicitly
    ; marked the 4/5-choice layout safe to continue.
    if (
        screenInfo["NeedsRescan"]
        || (
            ChoiceLabelsContainUnknown(screenInfo["Labels"])
            && !partialRarityOk
        )
        || expectedCount < 1
        || expectedCount > 5
        || detectedMode = "unknown"
    ) {

        choiceStatusText.Text := "Rarity/count unclear - rescanning colors"

        resultMap["FoundSlots"] := Map()
        resultMap["Count"] := 0
        resultMap["Mode"] := ""
        resultMap["HighestTolerance"] := 0
        resultMap["CanChoose"] := false
        resultMap["Action"] := "rescan"
        resultMap["RescanReason"] := "Rarity/count unclear"

        return resultMap
    }

    SetSearchAreaForChoiceCount(expectedCount)
    SetChoiceSlotCount(expectedCount)

    startTolerance := Max(15, sessionDefaultTolerance)

    finalResults := Map()
    finalMode := ""
    highestTolerance := 0

    ; ========================================================
    ; MIXED / MYTHIC / LIMITED: color evidence already confirms weapon.
    ; ========================================================

    if detectedMode = "weapon" {

        choiceStatusText.Text :=
            expectedCount
            . "-choice weapon screen - scanning weapons"

        finalResults := ScanWeaponChoicesByColorCount(
            expectedCount,
            startTolerance,
            &details,
            recoveryMode
        )

        finalMode := "weapon"
    }

    ; ========================================================
    ; SAME-COLOR COMMON/RARE/EPIC/LEGENDARY:
    ; image evidence decides upgrade vs same-color weapon.
    ; ========================================================

    else if detectedMode = "same_color_candidate" {

        choiceStatusText.Text :=
            expectedCount
            . "-choice "
            . detectedRarity
            . " screen - confirming upgrade vs weapon"

        typeEvidence := ClassifySameColorChoiceScreen(
            expectedCount,
            detectedRarity,
            startTolerance,
            &details,
            recoveryMode
        )

        confirmedMode := typeEvidence["Mode"]

        if confirmedMode = "ambiguous" {

            details .=
                "Upgrade/weapon evidence was ambiguous; rescanning colors/type.`r`n"

            UpdateScanDetails(details, true)

            choiceStatusText.Text :=
                "Could not safely confirm upgrade vs weapon - rescanning"

            resultMap["FoundSlots"] := Map()
            resultMap["Count"] := 0
            resultMap["Mode"] := ""
            resultMap["HighestTolerance"] := 0
            resultMap["CanChoose"] := false
            resultMap["Action"] := "rescan"
            resultMap["RescanReason"] := "Upgrade/weapon type unclear"

            return resultMap
        }

        if confirmedMode = "upgrade" {

            finalMode := "upgrade"
            finalResults := typeEvidence["UpgradeResults"]

            details .=
                "Image evidence confirmed "
                . detectedRarity
                . " upgrade screen.`r`n"

            UpdateScanDetails(details, true)

            ; Per-rarity reroll is now only allowed AFTER the script
            ; has proved this is actually an upgrade screen.
            if (
                allowReroll
                && rerollsLeft > 0
                && IsRerollEnabledForRarity(detectedRarity)
            ) {

                if PerformReroll(detectedRarity) {

                    resultMap["FoundSlots"] := Map()
                    resultMap["Count"] := 0
                    resultMap["Mode"] := "upgrade"
                    resultMap["HighestTolerance"] := 0
                    resultMap["CanChoose"] := false
                    resultMap["Action"] := "reroll"

                    return resultMap
                }
            }

            ContinueChoiceCategoryScan(
                typeEvidence["UpgradeNames"],
                typeEvidence["UpgradeTypeLabel"],
                typeEvidence["UpgradeFolderPath"],
                expectedCount,
                typeEvidence["LastTolerance"] + 15,
                finalResults,
                &details,
                detectedRarity " upgrades",
                recoveryMode
            )
        }
        else {

            finalMode := "weapon"
            finalResults := typeEvidence["WeaponResults"]

            details .=
                "Image evidence confirmed same-color weapon screen.`r`n"

            UpdateScanDetails(details, true)

            ContinueChoiceCategoryScan(
                typeEvidence["WeaponNames"],
                "Weapon",
                weaponFolder,
                expectedCount,
                typeEvidence["LastTolerance"] + 15,
                finalResults,
                &details,
                "Weapons",
                recoveryMode
            )
        }
    }

    highestTolerance := GetHighestToleranceInSlots(finalResults)

    resultMap["FoundSlots"] := finalResults
    resultMap["Count"] := finalResults.Count
    resultMap["Mode"] := finalMode
    resultMap["HighestTolerance"] := highestTolerance

    scanMs := A_TickCount - scanStartedAt
    resultMap["ScanMs"] := scanMs
    scanSeconds := Round(scanMs / 1000, 2)

    PopulateFinalChoiceGui(finalResults, expectedCount)

    ; ========================================================
    ; BANISH
    ; ========================================================

    if (
        allowBanish
        && finalMode = "upgrade"
        && banishesLeft > 0
    ) {

        banishCandidate := GetBanishCandidate(
            finalResults,
            detectedRarity
        )

        if IsObject(banishCandidate) {
            resultMap["Banish"] := banishCandidate
            UpdateBanishChoice(banishCandidate)
        }
        else {
            ClearBanishChoice()
        }
    }
    else {
        ClearBanishChoice()
    }

    ; ========================================================
    ; WEAPON REROLL
    ; ========================================================

    if (
        allowReroll
        && finalMode = "weapon"
        && rerollsLeft > 0
        && finalResults.Count = expectedCount
        && ShouldRerollWeaponChoices(finalResults)
    ) {

        details .=
            "Only below-REROLL selectable weapons found; rerolling.`r`n"

        UpdateScanDetails(details, true)

        if PerformReroll("weapon") {

            resultMap["FoundSlots"] := Map()
            resultMap["Count"] := 0
            resultMap["Mode"] := "weapon"
            resultMap["HighestTolerance"] := highestTolerance
            resultMap["CanChoose"] := false
            resultMap["Action"] := "reroll"

            return resultMap
        }
    }

    UpdateScanDetails(details, true)

    ; ========================================================
    ; CHOOSE SAFELY
    ; ========================================================

    ; A positively ImageSearch-matched card has a fresh exact coordinate.
    ; Do not require 3/5 cards just to make progress on a 5-choice screen.
    ; Missing identities can affect priority quality, but they should not
    ; freeze the macro forever.
    minimumConfirmed := 1

    enoughConfirmed := (
        finalResults.Count >= minimumConfirmed
    )

    bestResult := 0

    if enoughConfirmed
        bestResult := GetBestChoice(finalResults)

    ; Anti-stuck limit fallback: if every positively matched card is
    ; currently blocked by its configured selection limit, choose the
    ; highest-priority CONFIRMED image anyway. This never blind-clicks an
    ; unknown slot and prevents a partial scan from looping forever.
    if (
        !IsObject(bestResult)
        && finalResults.Count > 0
    ) {

        bestResult := GetBestChoiceIgnoringLimits(finalResults)

        if IsObject(bestResult) {
            details .=
                "All currently confirmed choices were at their selection limit; "
                . "using confirmed priority fallback to keep the run moving.`r`n"

            UpdateScanDetails(details, true)
        }
    }

    canChoose := IsObject(bestResult)

    resultMap["CanChoose"] := canChoose

    if canChoose {

        resultMap["Best"] := bestResult
        UpdateBestChoice(bestResult)

        choiceStatusText.Text :=
            "Confirmed "
            . finalMode
            . " | "
            . finalResults.Count
            . "/"
            . expectedCount
            . " matched | *"
            . highestTolerance
            . " | "
            . scanSeconds
            . "s"

    }
    else {

        ; No safe eligible choice from the confirmed images.
        ; Do not blindly click or keep using stale coordinates.
        choiceStatusText.Text :=
            "No safe confirmed choice - rescanning"

        resultMap["Action"] := "rescan"
        resultMap["RescanReason"] :=
            "No selectable image matched (" finalResults.Count "/" expectedCount ")"

        details .=
            "No safe Best result from confirmed choices; rescanning screen.`r`n"

        UpdateScanDetails(details, true)
    }

    return resultMap
}


; ============================================================
; POST-BANISH DIRECT RESCAN
; ============================================================
; Banish removes exactly one upgrade. Do not run the normal 3/4/5
; rarity-layout detector again because a 3-choice screen can become
; a valid 2-choice screen. Instead, use the known previous count and
; known rarity, then ImageSearch the new physical positions directly.

; ============================================================
; SELECTION LIMITS
; ============================================================

GetAllUpgradeNames() {
    global commonUpgrades
    global rareUpgrades
    global epicUpgrades
    global legendaryUpgrades
    global BANISH_MARKER
    names := []
    for source in [commonUpgrades, rareUpgrades, epicUpgrades, legendaryUpgrades] {
        for name in source {
            if name != BANISH_MARKER
                names.Push(name)
        }
    }
    return names
}

LoadUpgradeLimits() {

    global settingsFile

    limits := Map()

    for name in GetAllUpgradeNames() {

        savedValue := IniRead(
            settingsFile,
            "UpgradeLimits",
            name,
            "10"
        )

        try {
            limit := Integer(savedValue)
        }
        catch {
            limit := 10
        }

        if limit < 1
            limit := 1
        else if limit > 20
            limit := 20

        limits[name] := limit
    }

    return limits
}

ResetSelectionCounts() {

    global weaponPriority
    global weaponRemaining
    global upgradeMaxSelections
    global upgradeRemaining
    global WEAPON_REROLL_MARKER

    weaponRemaining := Map()

    for weapon in weaponPriority {
        if weapon != WEAPON_REROLL_MARKER
            weaponRemaining[weapon] := 5
    }

    upgradeRemaining := Map()

    for name, limit in upgradeMaxSelections
        upgradeRemaining[name] := limit
}

IsWeaponSearchable(weapon) {

    global weaponRemaining
    return weaponRemaining.Get(weapon, 5) > 0
}

RegisterChoiceSelection(result) {

    global weaponRemaining
    global upgradeRemaining

    name := result["Name"]
    type := result["Type"]

    if type = "Weapon" {

        remaining := weaponRemaining.Get(name, 5)

        if remaining > 0
            weaponRemaining[name] := remaining - 1

    }
    else {

        remaining := upgradeRemaining.Get(name, 10)

        if remaining > 0
            upgradeRemaining[name] := remaining - 1
    }
}

CopyMap(sourceMap) {

    copy := Map()

    for key, value in sourceMap
        copy[key] := value

    return copy
}

SaveUpgradeLimits() {

    global settingsFile
    global upgradeMaxSelections

    for name, limit in upgradeMaxSelections
        IniWrite limit, settingsFile, "UpgradeLimits", name
}

; ============================================================
; PRIORITY LIMIT GUI HELPERS
; ============================================================

CreateUpgradeLimitControls(priorityArray, baseX, baseY) {
    global priorityGui
    global editUpgradeLimits
    global upgradeLimitOptions
    global BANISH_MARKER
    controls := []
    rowStep := 21
    for index, name in priorityArray {
        selectedLimit := name = BANISH_MARKER ? 1 : editUpgradeLimits.Get(name, 10)
        control := priorityGui.AddDropDownList(
            "x" PGS(baseX) " y" PGS(baseY + ((index - 1) * rowStep)) " w" PGS(48) " Choose" selectedLimit,
            upgradeLimitOptions
        )
        control.OnEvent("Change", UpgradeLimitChanged.Bind(priorityArray, index, control))
        controls.Push(control)
    }
    RefreshUpgradeLimitControls(priorityArray, controls)
    return controls
}

UpgradeLimitChanged(priorityArray, index, control, *) {
    global editUpgradeLimits
    global BANISH_MARKER
    if index > priorityArray.Length
        return
    name := priorityArray[index]
    if name = BANISH_MARKER
        return
    editUpgradeLimits[name] := Integer(control.Text)
    SetPriorityStatus("Limit changed - click Save Priorities to keep it.")
}

RefreshUpgradeLimitControls(priorityArray, controls) {
    global editUpgradeLimits
    global BANISH_MARKER
    for index, control in controls {
        if index > priorityArray.Length {
            control.Visible := false
            control.Enabled := false
            continue
        }
        name := priorityArray[index]
        if name = BANISH_MARKER {
            control.Visible := false
            control.Enabled := false
            continue
        }
        control.Visible := true
        control.Enabled := true
        limit := editUpgradeLimits.Get(name, 10)
        control.Choose(limit)
    }
}

PGS(value) {

    global use720Mode

    ; Keep the priority editor larger than the other GUIs on 720p
    ; so all per-upgrade limit dropdowns remain readable.
    scale := use720Mode ? 0.90 : 1

    return Max(1, Round(value * scale))
}


; ============================================================
; SETTINGS GUI
; ============================================================

OpenSettings(*) {

    global settingsGui
    global settingsButton
    global settingsHotkeyValueText
    global settingsPendingHotkey
    global settingsPauseHotkeyValueText
    global settingsPendingPauseHotkey
    global settingsDarkModeCheckbox
    global settingsStatusText
    global settingsRerollsDropdown
    global settingsBanishesDropdown
    global closeScriptHotkey
    global pauseScriptHotkey
    global darkModeEnabled
    global rerollsPerLife
    global banishesPerLife
    global use720Mode

    settingsButton.Enabled := false

    if IsObject(settingsGui) {
        settingsPendingHotkey := closeScriptHotkey
        settingsPendingPauseHotkey := pauseScriptHotkey
        settingsHotkeyValueText.Value := closeScriptHotkey
        settingsPauseHotkeyValueText.Value := pauseScriptHotkey
        settingsDarkModeCheckbox.Value := darkModeEnabled ? 1 : 0
        settingsRerollsDropdown.Choose(rerollsPerLife + 1)
        settingsBanishesDropdown.Choose(banishesPerLife + 1)
        settingsStatusText.Text := ""
        ApplyThemeToGui(settingsGui)
        settingsGui.Show()
        return
    }

    settingsGui := Gui("+AlwaysOnTop +Border", "Settings")
    SetGuiBaseTheme(settingsGui)
    settingsGui.SetFont(ThemeFontOptions(use720Mode ? "s8" : "s9"), "Segoe UI")
    settingsPendingHotkey := closeScriptHotkey
    settingsPendingPauseHotkey := pauseScriptHotkey

    settingsGui.AddText("xm ym w" GS(230), "Close script keybind:")
    settingsHotkeyValueText := settingsGui.AddEdit(
        "xm y+" GS(5) " w" GS(120) " h" GS(24) " ReadOnly Center",
        closeScriptHotkey
    )
    setCloseKeybindButton := settingsGui.AddButton(
        "x+" GS(8) " yp-1 w" GS(102) " h" GS(24),
        "Set Keybind"
    )
    setCloseKeybindButton.OnEvent("Click", OpenKeybindCaptureGui.Bind("close"))

    settingsGui.AddText("xm y+" GS(14) " w" GS(230), "Pause farming keybind:")
    settingsPauseHotkeyValueText := settingsGui.AddEdit(
        "xm y+" GS(5) " w" GS(120) " h" GS(24) " ReadOnly Center",
        pauseScriptHotkey
    )
    setPauseKeybindButton := settingsGui.AddButton(
        "x+" GS(8) " yp-1 w" GS(102) " h" GS(24),
        "Set Keybind"
    )
    setPauseKeybindButton.OnEvent("Click", OpenKeybindCaptureGui.Bind("pause"))

    settingsGui.AddText("xm y+" GS(14) " w" GS(145), "Amount of rerolls:")
    settingsRerollsDropdown := settingsGui.AddDropDownList(
        "x+" GS(8) " yp-3 w" GS(70) " Choose" (rerollsPerLife + 1),
        ["0", "1", "2", "3"]
    )

    settingsGui.AddText("xm y+" GS(14) " w" GS(145), "Banishes:")
    settingsBanishesDropdown := settingsGui.AddDropDownList(
        "x+" GS(8) " yp-3 w" GS(70) " Choose" (banishesPerLife + 1),
        ["0", "1", "2"]
    )

    settingsDarkModeCheckbox := settingsGui.AddCheckBox(
        "xm y+" GS(14) " w" GS(230),
        "Dark mode for all GUIs"
    )
    settingsDarkModeCheckbox.Value := darkModeEnabled ? 1 : 0

    saveSettingsButton := settingsGui.AddButton(
        "xm y+" GS(14) " w" GS(108) " h" GS(30),
        "Save"
    )
    closeSettingsButton := settingsGui.AddButton(
        "x+" GS(8) " yp w" GS(108) " h" GS(30),
        "Close"
    )
    settingsStatusText := settingsGui.AddText(
        "xm y+" GS(10) " w" GS(230) " h" GS(42) " Center",
        ""
    )

    saveSettingsButton.OnEvent("Click", SaveAppSettings)
    closeSettingsButton.OnEvent("Click", CloseSettingsGui)
    settingsGui.OnEvent("Close", CloseSettingsGui)
    ApplyThemeToGui(settingsGui)
    settingsGui.Show("AutoSize")
}

CloseSettingsGui(*) {

    global settingsGui
    global settingsButton
    global keybindCaptureGui

    if IsObject(settingsGui)
        settingsGui.Hide()

    if IsObject(keybindCaptureGui)
        keybindCaptureGui.Hide()

    if IsObject(settingsButton)
        settingsButton.Enabled := true

    return true
}

OpenKeybindCaptureGui(target := "close", *) {

    global keybindCaptureGui
    global keybindCaptureStatusText
    global keybindCaptureTarget
    global use720Mode
    global settingsGui

    keybindCaptureTarget := target

    if IsObject(settingsGui)
        settingsGui.Hide()

    targetLabel := target = "pause" ? "pause-farming" : "close-script"

    if IsObject(keybindCaptureGui) {
        keybindCaptureStatusText.Text := "Press a key to set the " targetLabel " keybind."
        ApplyThemeToGui(keybindCaptureGui)
        keybindCaptureGui.Show()
    }
    else {
        keybindCaptureGui := Gui("+AlwaysOnTop +Border", "Set Keybind")
        SetGuiBaseTheme(keybindCaptureGui)
        keybindCaptureGui.SetFont(ThemeFontOptions(use720Mode ? "s8" : "s9"), "Segoe UI")
        keybindCaptureGui.AddText("xm ym w" GS(250) " Center", "Press a key to set keybind")
        keybindCaptureStatusText := keybindCaptureGui.AddText(
            "xm y+" GS(10) " w" GS(250) " h" GS(36) " Center",
            "Press a key to set the " targetLabel " keybind."
        )
        cancelCaptureButton := keybindCaptureGui.AddButton(
            "xm y+" GS(10) " w" GS(250) " h" GS(30),
            "Cancel"
        )
        cancelCaptureButton.OnEvent("Click", CancelKeybindCapture)
        keybindCaptureGui.OnEvent("Close", CancelKeybindCapture)
        ApplyThemeToGui(keybindCaptureGui)
        keybindCaptureGui.Show("AutoSize")
    }

    SetTimer BeginKeybindCapture, -50
}

CancelKeybindCapture(*) {

    global keybindCaptureGui
    global settingsGui

    if IsObject(keybindCaptureGui)
        keybindCaptureGui.Hide()

    if IsObject(settingsGui) {
        ApplyThemeToGui(settingsGui)
        settingsGui.Show()
    }

    return true
}

BeginKeybindCapture() {

    global keybindCaptureStatusText

    if IsObject(keybindCaptureStatusText)
        keybindCaptureStatusText.Text := "Waiting for key press..."

    ih := InputHook("L1")
    ih.KeyOpt("{All}", "E")
    ih.Start()
    ih.Wait()

    capturedKey := ih.EndKey

    if capturedKey = ""
        capturedKey := ih.Input

    if capturedKey = "" {
        if IsObject(keybindCaptureStatusText)
            keybindCaptureStatusText.Text := "No key detected. Try again."
        return
    }

    ApplyCapturedKeybind(capturedKey)
}

ApplyCapturedKeybind(capturedKey) {

    global settingsPendingHotkey
    global settingsHotkeyValueText
    global settingsPendingPauseHotkey
    global settingsPauseHotkeyValueText
    global settingsStatusText
    global keybindCaptureGui
    global keybindCaptureTarget
    global settingsGui

    switch capturedKey {
        case "Escape":
            capturedKey := "Esc"
        case "Backspace":
            capturedKey := "Backspace"
        case "Delete":
            capturedKey := "Delete"
        case "Space":
            capturedKey := "Space"
        case "Enter":
            capturedKey := "Enter"
        case "Tab":
            capturedKey := "Tab"
    }

    if keybindCaptureTarget = "pause" {
        settingsPendingPauseHotkey := capturedKey
        if IsObject(settingsPauseHotkeyValueText)
            settingsPauseHotkeyValueText.Value := capturedKey
        if IsObject(settingsStatusText)
            settingsStatusText.Text := "Pending pause hotkey: " capturedKey
    }
    else {
        settingsPendingHotkey := capturedKey
        if IsObject(settingsHotkeyValueText)
            settingsHotkeyValueText.Value := capturedKey
        if IsObject(settingsStatusText)
            settingsStatusText.Text := "Pending close hotkey: " capturedKey
    }

    if IsObject(keybindCaptureGui)
        keybindCaptureGui.Hide()

    if IsObject(settingsGui) {
        ApplyThemeToGui(settingsGui)
        settingsGui.Show()
    }
}

SaveAppSettings(*) {

    global settingsPendingHotkey
    global settingsHotkeyValueText
    global settingsPendingPauseHotkey
    global settingsPauseHotkeyValueText
    global settingsDarkModeCheckbox
    global settingsStatusText
    global settingsRerollsDropdown
    global settingsBanishesDropdown
    global closeScriptHotkey
    global pauseScriptHotkey
    global darkModeEnabled
    global rerollsPerLife
    global banishesPerLife
    global farmingStarted
    global settingsFile

    newCloseHotkey := Trim(settingsPendingHotkey)
    newPauseHotkey := Trim(settingsPendingPauseHotkey)

    if newCloseHotkey = "" {
        settingsStatusText.Text := "Choose a close-script keybind first."
        return
    }
    if newPauseHotkey = "" {
        settingsStatusText.Text := "Choose a pause-farming keybind first."
        return
    }
    if newCloseHotkey = newPauseHotkey {
        settingsStatusText.Text := "Close and pause keybinds must be different."
        return
    }

    oldCloseHotkey := closeScriptHotkey
    oldPauseHotkey := pauseScriptHotkey
    oldCloseRegistered := GetCloseHotkeyRegistrationName(oldCloseHotkey)
    oldPauseRegistered := GetCloseHotkeyRegistrationName(oldPauseHotkey)
    newCloseRegistered := GetCloseHotkeyRegistrationName(newCloseHotkey)
    newPauseRegistered := GetCloseHotkeyRegistrationName(newPauseHotkey)

    try Hotkey oldCloseRegistered, StopFarm, "Off"
    try Hotkey oldPauseRegistered, PauseFarm, "Off"

    hotkeysValid := true
    try {
        Hotkey newCloseRegistered, StopFarm, "On T2"
        Hotkey newPauseRegistered, PauseFarm, "On T2"
    }
    catch Error as e {
        hotkeysValid := false
    }

    if !hotkeysValid {
        try Hotkey newCloseRegistered, StopFarm, "Off"
        try Hotkey newPauseRegistered, PauseFarm, "Off"
        try Hotkey oldCloseRegistered, StopFarm, "On T2"
        try Hotkey oldPauseRegistered, PauseFarm, "On T2"
        settingsPendingHotkey := oldCloseHotkey
        settingsPendingPauseHotkey := oldPauseHotkey
        settingsHotkeyValueText.Value := oldCloseHotkey
        settingsPauseHotkeyValueText.Value := oldPauseHotkey
        settingsStatusText.Text := "Invalid/unavailable keybind."
        return
    }

    closeScriptHotkey := newCloseHotkey
    pauseScriptHotkey := newPauseHotkey
    IniWrite(closeScriptHotkey, settingsFile, "Interface", "CloseHotkey")
    IniWrite(pauseScriptHotkey, settingsFile, "Interface", "PauseHotkey")

    rerollsPerLife := Integer(settingsRerollsDropdown.Text)
    banishesPerLife := Integer(settingsBanishesDropdown.Text)
    if rerollsPerLife < 0
        rerollsPerLife := 0
    else if rerollsPerLife > 3
        rerollsPerLife := 3
    if banishesPerLife < 0
        banishesPerLife := 0
    else if banishesPerLife > 2
        banishesPerLife := 2

    IniWrite(rerollsPerLife, settingsFile, "Actions", "RerollsPerLife")
    IniWrite(banishesPerLife, settingsFile, "Actions", "BanishesPerLife")

    ; Do not replenish a currently paused/active run just because settings changed.
    if !farmingStarted
        ResetLifeActionCounts()

    newDarkMode := settingsDarkModeCheckbox.Value = 1
    if newDarkMode != darkModeEnabled {
        darkModeEnabled := newDarkMode
        IniWrite(darkModeEnabled ? "1" : "0", settingsFile, "Interface", "DarkMode")
        ApplyThemeToAllGuis()
    }
    else {
        IniWrite(darkModeEnabled ? "1" : "0", settingsFile, "Interface", "DarkMode")
    }

    settingsStatusText.Text := "Saved | Pause: " pauseScriptHotkey " | Rerolls: " rerollsPerLife " | Banishes: " banishesPerLife
}

CheckPauseHotkeyPhysical() {

    global farmingStarted
    global farmPaused
    global pauseScriptHotkey
    global pauseHotkeyWasDown

    if !farmingStarted || pauseScriptHotkey = "" {
        pauseHotkeyWasDown := false
        return
    }

    if farmPaused
        return

    try {
        keyDown := GetKeyState(pauseScriptHotkey, "P")
        if keyDown && !pauseHotkeyWasDown {
            pauseHotkeyWasDown := true
            PauseFarm()
            return
        }
        if !keyDown
            pauseHotkeyWasDown := false
    }
}


InitializePauseHotkey() {

    global pauseScriptHotkey
    global settingsFile

    registeredHotkey := GetCloseHotkeyRegistrationName(pauseScriptHotkey)

    try {
        Hotkey registeredHotkey, PauseFarm, "On T2"
    }
    catch Error as e {
        pauseScriptHotkey := "P"
        IniWrite(pauseScriptHotkey, settingsFile, "Interface", "PauseHotkey")
        registeredHotkey := GetCloseHotkeyRegistrationName(pauseScriptHotkey)
        Hotkey registeredHotkey, PauseFarm, "On T2"
    }

    SetTimer CheckPauseHotkeyPhysical, 25
}


PauseFarm(*) {

    global farmingStarted
    global farmPaused
    global autoClicking
    global choiceGui
    global pauseHotkeyWasDown

    ; Pause key is one-way. Pressing it while paused does nothing.
    if !farmingStarted || farmPaused
        return

    farmPaused := true
    pauseHotkeyWasDown := true
    autoClicking := false

    SetTimer CheckDeath, 0

    if IsObject(choiceGui)
        choiceGui.Hide()

    BlockInput "MouseMoveOff"
    ShowPauseGui()

    ; Suspend the interrupted farming/timer thread underneath this hotkey.
    try Pause true
}


ResumeFarmFromPause(*) {

    global farmingStarted
    global farmPaused
    global resumeToWhiteRequested
    global pauseGui
    global choiceGui
    global choiceGuiX
    global choiceGuiY
    global whiteRestX
    global whiteRestY
    global restartInProgress

    if !farmingStarted || !farmPaused
        return

    answer := MsgBox(
        "Did you start a new run while paused?`n`n"
        . "Yes = reset run selections, rerolls, and banishes.`n"
        . "No = keep the current run's remaining rerolls and banishes.",
        "Resume Farming",
        "YesNo Icon?"
    )

    if answer = "Yes" {
        ResetSelectionCounts()
        ResetLifeActionCounts()
        restartInProgress := false
    }

    ; Any pre-pause scan/choice data is stale. Return to white detection.
    resumeToWhiteRequested := true
    farmPaused := false

    if IsObject(pauseGui)
        pauseGui.Hide()

    HidePauseUtilityGuis()
    ResetChoiceGui("Resumed - checking for white...")

    if IsObject(choiceGui) {
        choiceGui.Show("x" choiceGuiX " y" choiceGuiY)
        PositionChoiceGuiTopRight()
    }

    BlockInput "MouseMove"
    MouseMove whiteRestX, whiteRestY, 2
    SetTimer CheckDeath, 2000

    try Pause false
}


ConsumeResumeToWhiteRequest() {
    global resumeToWhiteRequested
    if !resumeToWhiteRequested
        return false
    resumeToWhiteRequested := false
    return true
}


ShouldAbortCurrentActionForResume() {
    global resumeToWhiteRequested
    return resumeToWhiteRequested
}

GetCloseHotkeyRegistrationName(keyName) {
    return "$" . keyName
}

CheckCloseHotkeyPhysical() {
    global farmingStarted
    global closeScriptHotkey

    if !farmingStarted || closeScriptHotkey = ""
        return

    try {
        if GetKeyState(closeScriptHotkey, "P")
            StopFarm()
    }
}

CheckCloseNow() {

    global farmingStarted
    global closeScriptHotkey
    global farmPaused

    if !farmingStarted || closeScriptHotkey = ""
        return

    try {
        if GetKeyState(closeScriptHotkey, "P")
            StopFarm()
    }

    ; Normally the underlying thread is hard-paused. This is a backup gate
    ; for any timer/thread which was not directly underneath PauseFarm.
    while farmPaused {
        try {
            if GetKeyState(closeScriptHotkey, "P")
                StopFarm()
        }
        Sleep 25
    }
}

InitializeCloseHotkey() {
    global closeScriptHotkey
    global settingsFile

    registeredHotkey := GetCloseHotkeyRegistrationName(closeScriptHotkey)

    try {
        Hotkey registeredHotkey, StopFarm, "On T2"
    }
    catch Error as e {
        closeScriptHotkey := "\"
        IniWrite(closeScriptHotkey, settingsFile, "Interface", "CloseHotkey")
        registeredHotkey := GetCloseHotkeyRegistrationName(closeScriptHotkey)
        Hotkey registeredHotkey, StopFarm, "On T2"
    }

    SetTimer CheckCloseHotkeyPhysical, 25
}

; ============================================================
; SAVED SELECTIONS
; ============================================================

LoadSavedSelections() {

    global settingsFile
    global islandDropdown
    global challengeDropdown
    global difficultyDropdown
    global defaultToleranceDropdown
    global islandOptions
    global challengeOptions
    global difficultyOptions
    global toleranceOptions
    global sessionDefaultTolerance

    savedIsland := IniRead(settingsFile, "Game", "Island", "Grasslands")
    savedChallenge := IniRead(settingsFile, "Game", "Challenge", "None")
    savedDifficulty := IniRead(settingsFile, "Game", "Difficulty", "Normal")
    savedTolerance := IniRead(settingsFile, "Game", "DefaultTolerance", "15")

    ChooseSavedItem(islandDropdown, islandOptions, savedIsland)
    ChooseSavedItem(challengeDropdown, challengeOptions, savedChallenge)
    ChooseSavedItem(difficultyDropdown, difficultyOptions, savedDifficulty)
    ChooseSavedItem(defaultToleranceDropdown, toleranceOptions, savedTolerance)

    sessionDefaultTolerance := Integer(defaultToleranceDropdown.Text)
}

SaveSelections(*) {

    global settingsFile
    global islandDropdown
    global challengeDropdown
    global difficultyDropdown
    global defaultToleranceDropdown

    IniWrite islandDropdown.Text, settingsFile, "Game", "Island"
    IniWrite challengeDropdown.Text, settingsFile, "Game", "Challenge"
    IniWrite difficultyDropdown.Text, settingsFile, "Game", "Difficulty"
    IniWrite defaultToleranceDropdown.Text, settingsFile, "Game", "DefaultTolerance"
}

DefaultToleranceChanged(*) {

    global sessionDefaultTolerance
    global defaultToleranceDropdown

    sessionDefaultTolerance := Integer(defaultToleranceDropdown.Text)

    SaveSelections()
    UpdateToleranceDisplays()
}

ChooseSavedItem(control, options, savedValue) {

    for index, item in options {
        if item = savedValue {
            control.Choose(index)
            return
        }
    }

    control.Choose(1)
}

; ============================================================
; PRIORITY EDITOR
; ============================================================

OpenPriorities(*) {

    global use720Mode
    global priorityGui
    global prioritiesButton

    global commonUpgrades
    global rareUpgrades
    global epicUpgrades
    global legendaryUpgrades
    global weaponPriority

    global commonEditPriority
    global rareEditPriority
    global epicEditPriority
    global legendaryEditPriority
    global weaponEditPriority

    global commonEditList
    global rareEditList
    global epicEditList
    global legendaryEditList
    global weaponEditList

    global commonLimitControls
    global rareLimitControls
    global epicLimitControls
    global legendaryLimitControls

    global upgradeMaxSelections
    global editUpgradeLimits
    global priorityStatusText
    global commonRerollCheckbox
    global rareRerollCheckbox
    global epicRerollCheckbox
    global legendaryRerollCheckbox
    global rerollCommonEnabled
    global rerollRareEnabled
    global rerollEpicEnabled
    global rerollLegendaryEnabled

    if IsObject(priorityGui) {

        ; The Priorities GUI is persistent now. Closing it only hides it,
        ; so reopening should simply show the existing controls again.
        prioritiesButton.Enabled := false
        priorityGui.Show()
        return
    }

    commonEditPriority := CopyArray(commonUpgrades)
    rareEditPriority := CopyArray(rareUpgrades)
    epicEditPriority := CopyArray(epicUpgrades)
    legendaryEditPriority := CopyArray(legendaryUpgrades)
    weaponEditPriority := CopyArray(weaponPriority)

    editUpgradeLimits := CopyMap(upgradeMaxSelections)

    prioritiesButton.Enabled := false

    priorityGui := Gui("+Border", "Priorities")
    SetGuiBaseTheme(priorityGui)
    priorityGui.SetFont(
        ThemeFontOptions(use720Mode ? "s7" : "s8"),
        "Segoe UI"
    )

    priorityGui.AddText(
        "x" PGS(10) " y" PGS(10) " w" PGS(1165) " Center",
        "Top = highest priority | Move upgrades below BANISH to banish them | Move weapons below REROLL to reroll weapon-only screens | Max = selections before death"
    )

    ; ---------------- COMMON ----------------

    priorityGui.AddGroupBox(
        "x" PGS(10) " y" PGS(35) " w" PGS(225) " h" PGS(630),
        ""
    )

    priorityGui.AddText(
        "x" PGS(58) " y" PGS(35) " w" PGS(130) " Center",
        "Common"
    )

    priorityGui.AddText(
        "x" PGS(180) " y" PGS(55) " w" PGS(40) " Center",
        "Max"
    )

    commonEditList := priorityGui.AddListBox(
        "x" PGS(20) " y" PGS(80) " w" PGS(152) " h" PGS(520),
        commonEditPriority
    )

    commonEditList.SetFont(ThemeFontOptions(use720Mode ? "s10" : "s12"), "Segoe UI")

    commonLimitControls := CreateUpgradeLimitControls(
        commonEditPriority,
        180,
        80
    )

    commonUpButton := priorityGui.AddButton(
        "x" PGS(20) " y" PGS(610) " w" PGS(95) " h" PGS(30),
        "Move Up"
    )

    commonDownButton := priorityGui.AddButton(
        "x" PGS(125) " y" PGS(610) " w" PGS(95) " h" PGS(30),
        "Move Down"
    )

    commonUpButton.OnEvent(
        "Click",
        MovePriorityItem.Bind(
            commonEditList,
            commonEditPriority,
            commonLimitControls,
            -1
        )
    )

    commonDownButton.OnEvent(
        "Click",
        MovePriorityItem.Bind(
            commonEditList,
            commonEditPriority,
            commonLimitControls,
            1
        )
    )

    commonRerollCheckbox := priorityGui.AddCheckBox(
        "x" PGS(20) " y" PGS(642) " w" PGS(190) " h" PGS(20), "Reroll"
    )
    commonRerollCheckbox.Value := rerollCommonEnabled ? 1 : 0

    ; ---------------- RARE ----------------

    priorityGui.AddGroupBox(
        "x" PGS(245) " y" PGS(35) " w" PGS(225) " h" PGS(630),
        ""
    )

    priorityGui.AddText(
        "x" PGS(293) " y" PGS(35) " w" PGS(130) " Center",
        "Rare"
    )

    priorityGui.AddText(
        "x" PGS(415) " y" PGS(55) " w" PGS(40) " Center",
        "Max"
    )

    rareEditList := priorityGui.AddListBox(
        "x" PGS(255) " y" PGS(80) " w" PGS(152) " h" PGS(520),
        rareEditPriority
    )

    rareEditList.SetFont(ThemeFontOptions(use720Mode ? "s10" : "s12"), "Segoe UI")

    rareLimitControls := CreateUpgradeLimitControls(
        rareEditPriority,
        415,
        80
    )

    rareUpButton := priorityGui.AddButton(
        "x" PGS(255) " y" PGS(610) " w" PGS(95) " h" PGS(30),
        "Move Up"
    )

    rareDownButton := priorityGui.AddButton(
        "x" PGS(360) " y" PGS(610) " w" PGS(95) " h" PGS(30),
        "Move Down"
    )

    rareUpButton.OnEvent(
        "Click",
        MovePriorityItem.Bind(
            rareEditList,
            rareEditPriority,
            rareLimitControls,
            -1
        )
    )

    rareDownButton.OnEvent(
        "Click",
        MovePriorityItem.Bind(
            rareEditList,
            rareEditPriority,
            rareLimitControls,
            1
        )
    )

    rareRerollCheckbox := priorityGui.AddCheckBox(
        "x" PGS(255) " y" PGS(642) " w" PGS(190) " h" PGS(20), "Reroll"
    )
    rareRerollCheckbox.Value := rerollRareEnabled ? 1 : 0

    ; ---------------- EPIC ----------------

    priorityGui.AddGroupBox(
        "x" PGS(480) " y" PGS(35) " w" PGS(225) " h" PGS(630),
        ""
    )

    priorityGui.AddText(
        "x" PGS(528) " y" PGS(35) " w" PGS(130) " Center",
        "Epic"
    )

    priorityGui.AddText(
        "x" PGS(650) " y" PGS(55) " w" PGS(40) " Center",
        "Max"
    )

    epicEditList := priorityGui.AddListBox(
        "x" PGS(490) " y" PGS(80) " w" PGS(152) " h" PGS(520),
        epicEditPriority
    )

    epicEditList.SetFont(ThemeFontOptions(use720Mode ? "s10" : "s12"), "Segoe UI")

    epicLimitControls := CreateUpgradeLimitControls(
        epicEditPriority,
        650,
        80
    )

    epicUpButton := priorityGui.AddButton(
        "x" PGS(490) " y" PGS(610) " w" PGS(95) " h" PGS(30),
        "Move Up"
    )

    epicDownButton := priorityGui.AddButton(
        "x" PGS(595) " y" PGS(610) " w" PGS(95) " h" PGS(30),
        "Move Down"
    )

    epicUpButton.OnEvent(
        "Click",
        MovePriorityItem.Bind(
            epicEditList,
            epicEditPriority,
            epicLimitControls,
            -1
        )
    )

    epicDownButton.OnEvent(
        "Click",
        MovePriorityItem.Bind(
            epicEditList,
            epicEditPriority,
            epicLimitControls,
            1
        )
    )

    epicRerollCheckbox := priorityGui.AddCheckBox(
        "x" PGS(490) " y" PGS(642) " w" PGS(190) " h" PGS(20), "Reroll"
    )
    epicRerollCheckbox.Value := rerollEpicEnabled ? 1 : 0

    ; ---------------- LEGENDARY ----------------

    priorityGui.AddGroupBox(
        "x" PGS(715) " y" PGS(35) " w" PGS(225) " h" PGS(630),
        ""
    )

    priorityGui.AddText(
        "x" PGS(763) " y" PGS(35) " w" PGS(130) " Center",
        "Legendary"
    )

    priorityGui.AddText(
        "x" PGS(885) " y" PGS(55) " w" PGS(40) " Center",
        "Max"
    )

    legendaryEditList := priorityGui.AddListBox(
        "x" PGS(725) " y" PGS(80) " w" PGS(152) " h" PGS(520),
        legendaryEditPriority
    )

    legendaryEditList.SetFont(ThemeFontOptions(use720Mode ? "s10" : "s12"), "Segoe UI")

    legendaryLimitControls := CreateUpgradeLimitControls(
        legendaryEditPriority,
        885,
        80
    )

    legendaryUpButton := priorityGui.AddButton(
        "x" PGS(725) " y" PGS(610) " w" PGS(95) " h" PGS(30),
        "Move Up"
    )

    legendaryDownButton := priorityGui.AddButton(
        "x" PGS(830) " y" PGS(610) " w" PGS(95) " h" PGS(30),
        "Move Down"
    )

    legendaryUpButton.OnEvent(
        "Click",
        MovePriorityItem.Bind(
            legendaryEditList,
            legendaryEditPriority,
            legendaryLimitControls,
            -1
        )
    )

    legendaryDownButton.OnEvent(
        "Click",
        MovePriorityItem.Bind(
            legendaryEditList,
            legendaryEditPriority,
            legendaryLimitControls,
            1
        )
    )

    legendaryRerollCheckbox := priorityGui.AddCheckBox(
        "x" PGS(725) " y" PGS(642) " w" PGS(190) " h" PGS(20), "Reroll"
    )
    legendaryRerollCheckbox.Value := rerollLegendaryEnabled ? 1 : 0

    ; ---------------- WEAPONS ----------------

    priorityGui.AddGroupBox(
        "x" PGS(950) " y" PGS(35) " w" PGS(225) " h" PGS(630),
        ""
    )

    priorityGui.AddText(
        "x" PGS(980) " y" PGS(35) " w" PGS(165) " Center",
        "Weapons (5 each)"
    )

    weaponEditList := priorityGui.AddListBox(
        "x" PGS(960) " y" PGS(80) " w" PGS(205) " h" PGS(520),
        weaponEditPriority
    )

    weaponEditList.SetFont(ThemeFontOptions(use720Mode ? "s10" : "s12"), "Segoe UI")

    weaponUpButton := priorityGui.AddButton(
        "x" PGS(960) " y" PGS(610) " w" PGS(95) " h" PGS(30),
        "Move Up"
    )

    weaponDownButton := priorityGui.AddButton(
        "x" PGS(1065) " y" PGS(610) " w" PGS(95) " h" PGS(30),
        "Move Down"
    )

    weaponUpButton.OnEvent(
        "Click",
        MovePriorityItem.Bind(
            weaponEditList,
            weaponEditPriority,
            0,
            -1
        )
    )

    weaponDownButton.OnEvent(
        "Click",
        MovePriorityItem.Bind(
            weaponEditList,
            weaponEditPriority,
            0,
            1
        )
    )

    ; ---------------- BOTTOM ----------------

    savePriorityButton := priorityGui.AddButton(
        "x" PGS(285) " y" PGS(675) " w" PGS(190) " h" PGS(42),
        "Save Priorities"
    )

    restorePriorityButton := priorityGui.AddButton(
        "x" PGS(495) " y" PGS(675) " w" PGS(190) " h" PGS(42),
        "Restore Defaults"
    )

    closePriorityButton := priorityGui.AddButton(
        "x" PGS(705) " y" PGS(675) " w" PGS(190) " h" PGS(42),
        "Close"
    )

    priorityStatusText := priorityGui.AddText(
        "x" PGS(10) " y" PGS(735) " w" PGS(1165) " Center",
        "Upgrade limits default to 10. Weapon limit is always 5."
    )

    savePriorityButton.OnEvent("Click", SavePriorityEditor)
    restorePriorityButton.OnEvent("Click", RestorePriorityDefaults)
    closePriorityButton.OnEvent("Click", ClosePriorityEditor)

    priorityGui.OnEvent("Close", ClosePriorityEditor)

    ApplyThemeToGui(priorityGui)

    priorityGui.Show(
        "w" PGS(1185)
        . " h" PGS(775)
    )
}

SetPriorityStatus(message) {

    global priorityStatusText

    ; A stale/destroyed GUI control should never be able to crash
    ; priority saving or editing.
    try {
        if IsObject(priorityStatusText)
            priorityStatusText.Text := message
    }
}

MovePriorityItem(listControl, priorityArray, limitControls, direction, *) {
    global BANISH_MARKER
    global WEAPON_REROLL_MARKER

    selectedIndex := listControl.Value

    if selectedIndex = 0 {
        SetPriorityStatus("Select an item first.")
        return
    }

    if priorityArray[selectedIndex] = BANISH_MARKER {
        SetPriorityStatus("Move an upgrade across BANISH instead of moving the marker.")
        return
    }

    if priorityArray[selectedIndex] = WEAPON_REROLL_MARKER {
        SetPriorityStatus("Move a weapon across REROLL instead of moving the marker.")
        return
    }

    newIndex := selectedIndex + direction
    if newIndex < 1 || newIndex > priorityArray.Length
        return
    temp := priorityArray[selectedIndex]
    priorityArray[selectedIndex] := priorityArray[newIndex]
    priorityArray[newIndex] := temp
    RefreshPriorityList(listControl, priorityArray, newIndex)
    if IsObject(limitControls)
        RefreshUpgradeLimitControls(priorityArray, limitControls)
    SetPriorityStatus("Priority/banish zone changed - click Save Priorities to keep it.")
}

RefreshPriorityList(listControl, priorityArray, selectedIndex := 1) {

    listControl.Delete()
    listControl.Add(priorityArray)

    if priorityArray.Length > 0
        listControl.Choose(selectedIndex)
}

SavePriorityEditor(*) {

    global settingsFile
    global commonUpgrades
    global rareUpgrades
    global epicUpgrades
    global legendaryUpgrades
    global weaponPriority

    global commonEditPriority
    global rareEditPriority
    global epicEditPriority
    global legendaryEditPriority
    global weaponEditPriority

    global editUpgradeLimits
    global upgradeMaxSelections

    global priorityStatusText
    global commonRerollCheckbox
    global rareRerollCheckbox
    global epicRerollCheckbox
    global legendaryRerollCheckbox
    global rerollCommonEnabled
    global rerollRareEnabled
    global rerollEpicEnabled
    global rerollLegendaryEnabled

    CopyInto(commonUpgrades, commonEditPriority)
    CopyInto(rareUpgrades, rareEditPriority)
    CopyInto(epicUpgrades, epicEditPriority)
    CopyInto(legendaryUpgrades, legendaryEditPriority)
    CopyInto(weaponPriority, weaponEditPriority)

    upgradeMaxSelections := CopyMap(editUpgradeLimits)

    rerollCommonEnabled := commonRerollCheckbox.Value = 1
    rerollRareEnabled := rareRerollCheckbox.Value = 1
    rerollEpicEnabled := epicRerollCheckbox.Value = 1
    rerollLegendaryEnabled := legendaryRerollCheckbox.Value = 1

    IniWrite ArrayToString(commonUpgrades), settingsFile, "Priorities", "Common"
    IniWrite ArrayToString(rareUpgrades), settingsFile, "Priorities", "Rare"
    IniWrite ArrayToString(epicUpgrades), settingsFile, "Priorities", "Epic"
    IniWrite ArrayToString(legendaryUpgrades), settingsFile, "Priorities", "Legendary"
    IniWrite ArrayToString(weaponPriority), settingsFile, "Priorities", "Weapons"
    IniWrite (rerollCommonEnabled ? "1" : "0"), settingsFile, "RerollByRarity", "Common"
    IniWrite (rerollRareEnabled ? "1" : "0"), settingsFile, "RerollByRarity", "Rare"
    IniWrite (rerollEpicEnabled ? "1" : "0"), settingsFile, "RerollByRarity", "Epic"
    IniWrite (rerollLegendaryEnabled ? "1" : "0"), settingsFile, "RerollByRarity", "Legendary"

    SaveUpgradeLimits()

    ; Applying new limits starts the current run counters fresh.
    ResetSelectionCounts()


    ; Saving is complete before any GUI-only status update.
    SetPriorityStatus("Priorities, banish zones, reroll rules, and limits saved.")
}

RestorePriorityDefaults(*) {

    global commonDefaults
    global rareDefaults
    global epicDefaults
    global legendaryDefaults
    global weaponDefaults

    global commonEditPriority
    global rareEditPriority
    global epicEditPriority
    global legendaryEditPriority
    global weaponEditPriority

    global commonEditList
    global rareEditList
    global epicEditList
    global legendaryEditList
    global weaponEditList

    global commonLimitControls
    global rareLimitControls
    global epicLimitControls
    global legendaryLimitControls

    global editUpgradeLimits
    global priorityStatusText
    global commonRerollCheckbox
    global rareRerollCheckbox
    global epicRerollCheckbox
    global legendaryRerollCheckbox

    CopyInto(commonEditPriority, commonDefaults)
    CopyInto(rareEditPriority, rareDefaults)
    CopyInto(epicEditPriority, epicDefaults)
    CopyInto(legendaryEditPriority, legendaryDefaults)
    CopyInto(weaponEditPriority, weaponDefaults)

    for name in GetAllUpgradeNames()
        editUpgradeLimits[name] := 10

    RefreshPriorityList(commonEditList, commonEditPriority)
    RefreshPriorityList(rareEditList, rareEditPriority)
    RefreshPriorityList(epicEditList, epicEditPriority)
    RefreshPriorityList(legendaryEditList, legendaryEditPriority)
    RefreshPriorityList(weaponEditList, weaponEditPriority)

    RefreshUpgradeLimitControls(commonEditPriority, commonLimitControls)
    RefreshUpgradeLimitControls(rareEditPriority, rareLimitControls)
    RefreshUpgradeLimitControls(epicEditPriority, epicLimitControls)
    RefreshUpgradeLimitControls(legendaryEditPriority, legendaryLimitControls)
    commonRerollCheckbox.Value := 0
    rareRerollCheckbox.Value := 0
    epicRerollCheckbox.Value := 0
    legendaryRerollCheckbox.Value := 0

    SetPriorityStatus("Defaults restored - BANISH moved to bottom and rerolls unchecked. Save to keep.")
}

ClosePriorityEditor(*) {

    global priorityGui
    global prioritiesButton

    ; Hide instead of Destroy.
    ; Destroying the GUI invalidates all ListBox, dropdown, and status
    ; controls while callbacks may still hold references to them.
    if IsObject(priorityGui)
        priorityGui.Hide()

    prioritiesButton.Enabled := true
    return true
}

; ============================================================
; SETTINGS / ARRAY HELPERS
; ============================================================

LoadPriority(keyName, defaults) {
    global settingsFile
    global BANISH_MARKER
    global WEAPON_REROLL_MARKER

    saved := IniRead(settingsFile, "Priorities", keyName, "")

    if saved = ""
        return CopyArray(defaults)

    loaded := StrSplit(saved, "|")
    merged := []

    specialMarker := ""

    if keyName = "Weapons"
        specialMarker := WEAPON_REROLL_MARKER
    else
        specialMarker := BANISH_MARKER

    for savedItem in loaded {
        valid := false

        for defaultItem in defaults {
            if savedItem = defaultItem {
                valid := true
                break
            }
        }

        if !valid
            continue

        alreadyAdded := false

        for existingItem in merged {
            if existingItem = savedItem {
                alreadyAdded := true
                break
            }
        }

        if !alreadyAdded
            merged.Push(savedItem)
    }

    for defaultItem in defaults {

        found := false

        for existingItem in merged {
            if existingItem = defaultItem {
                found := true
                break
            }
        }

        if found
            continue

        if defaultItem = specialMarker {
            merged.Push(defaultItem)
            continue
        }

        markerIndex := 0

        for index, existingItem in merged {
            if existingItem = specialMarker {
                markerIndex := index
                break
            }
        }

        if markerIndex > 0
            merged.InsertAt(markerIndex, defaultItem)
        else
            merged.Push(defaultItem)
    }

    return merged
}


CopyArray(sourceArray) {

    copy := []

    for item in sourceArray
        copy.Push(item)

    return copy
}

CopyInto(targetArray, sourceArray) {

    while targetArray.Length > 0
        targetArray.Pop()

    for item in sourceArray
        targetArray.Push(item)
}

ArrayToString(array) {

    output := ""

    for index, item in array {

        if index > 1
            output .= "|"

        output .= item
    }

    return output
}

; ============================================================
; START FARM
; ============================================================

StartFarm(*) {

    global farmGui
    global choiceGui
    global pauseGui
    global farmingStarted
    global farmPaused
    global resumeToWhiteRequested
    global restartInProgress
    global autoClicking
    global selectedIsland
    global selectedChallenge
    global selectedDifficulty
    global islandDropdown
    global challengeDropdown
    global difficultyDropdown
    global defaultToleranceDropdown
    global sessionDefaultTolerance

    if farmingStarted
        return

    RefreshScaledSearchArea()
    selectedIsland := islandDropdown.Text
    selectedChallenge := challengeDropdown.Text
    selectedDifficulty := difficultyDropdown.Text
    SaveSelections()

    farmingStarted := true
    farmPaused := false
    resumeToWhiteRequested := false
    restartInProgress := false
    autoClicking := false

    ResetSelectionCounts()
    ResetLifeActionCounts()
    sessionDefaultTolerance := Integer(defaultToleranceDropdown.Text)
    UpdateToleranceDisplays()
    ResetChoiceGui()
    farmGui.Hide()

    if IsObject(pauseGui)
        pauseGui.Hide()
    if IsObject(choiceGui)
        choiceGui.Hide()

    BlockInput "MouseMove"
    SetTimer CheckDeath, 2000
    RunFarm()
}

; ============================================================
; STOP
; ============================================================

StopFarm(*) {

    global farmingStarted
    global farmPaused
    global autoClicking
    global choiceGui
    global pauseGui

    farmingStarted := false
    farmPaused := false
    autoClicking := false

    SetTimer CheckDeath, 0
    SetTimer CheckCloseHotkeyPhysical, 0
    SetTimer CheckPauseHotkeyPhysical, 0

    if IsObject(choiceGui)
        choiceGui.Hide()
    if IsObject(pauseGui)
        pauseGui.Hide()

    BlockInput "MouseMoveOff"
    try Pause false
    ExitApp
}

InitializeCloseHotkey()
InitializePauseHotkey()

; ============================================================
; PIXEL WAIT WITH TIMEOUT
; ============================================================

WaitForPixelColor(
    x,
    y,
    targetColor,
    timeoutMs,
    intervalMs := 100
) {

    startedAt := A_TickCount

    while A_TickCount - startedAt < timeoutMs {

        CheckCloseNow()

        currentColor := PixelGetColor(
            x,
            y,
            "RGB"
        ) & 0xFFFFFF

        if currentColor = targetColor
            return true

        Sleep intervalMs
    }

    return false
}

; ============================================================
; CLICK UNTIL CALIBRATED COLOR DISAPPEARS
; ============================================================

ClickUntilPixelColorGone(
    sampleX,
    sampleY,
    targetColor,
    clickX,
    clickY,
    retryAfterMs := 10000,
    maxClickAttempts := 3,
    statusPrefix := "Button"
) {

    clickAttempts := 0

    Loop maxClickAttempts {

        CheckCloseNow()
        clickAttempts += 1

        currentColor := PixelGetColor(
            sampleX,
            sampleY,
            "RGB"
        ) & 0xFFFFFF

        if currentColor != targetColor
            return true

        ResetChoiceGui(
            statusPrefix
            . " still detected - click "
            . clickAttempts
            . "/"
            . maxClickAttempts
        )

        MouseMove clickX, clickY, 2
        Sleep 300
        CheckCloseNow()
        Click

        waitStartedAt := A_TickCount

        while A_TickCount - waitStartedAt < retryAfterMs {

            CheckCloseNow()

            currentColor := PixelGetColor(
                sampleX,
                sampleY,
                "RGB"
            ) & 0xFFFFFF

            if currentColor != targetColor
                return true

            Sleep 100
        }
    }

    return false
}

; ============================================================
; PLAY COLOR CHECK
; ============================================================

IsPlayColorDetected() {

    global playCalibratedColor

    playX := ScaleX(932)
    playY := ScaleY(1010)

    currentPlayColor := PixelGetColor(
        playX,
        playY,
        "RGB"
    ) & 0xFFFFFF

    expectedPlayColor := (
        playCalibratedColor != ""
        ? Integer(playCalibratedColor)
        : 0xDEF5DE
    )

    return currentPlayColor = expectedPlayColor
}

; ============================================================
; START GAME
; ============================================================

StartGame() {

    global whiteRestX
    global whiteRestY
    global selectedIsland
    global selectedChallenge
    global selectedDifficulty

    CheckCloseNow()
    if ShouldAbortCurrentActionForResume()
        return false

    MouseMove ScaleX(960), ScaleY(1000), 2
    Click
    Sleep 50
    CheckCloseNow()
    if ShouldAbortCurrentActionForResume()
        return false
    Click

    islandClicks := 0
    switch selectedIsland {
        case "Grasslands": islandClicks := 0
        case "Desert": islandClicks := 1
        case "Swamp": islandClicks := 2
        case "Jungle": islandClicks := 3
        case "Frost Forest": islandClicks := 4
    }

    MouseMove ScaleX(1730), ScaleY(550), 2
    Sleep 400
    Loop islandClicks {
        CheckCloseNow()
        if ShouldAbortCurrentActionForResume()
            return false
        Click
        Sleep 250
    }

    switch selectedDifficulty {
        case "Normal": MouseMove ScaleX(715), ScaleY(520), 2
        case "Hard": MouseMove ScaleX(960), ScaleY(520), 2
        case "Nightmare": MouseMove ScaleX(1200), ScaleY(520), 2
    }

    Sleep 400
    CheckCloseNow()
    if ShouldAbortCurrentActionForResume()
        return false
    Click

    MouseMove ScaleX(960), ScaleY(740), 2
    CheckCloseNow()
    if ShouldAbortCurrentActionForResume()
        return false
    Click

    if selectedChallenge = "Double Trouble" {
        MouseMove ScaleX(800), ScaleY(750), 1
        Loop 20 {
            CheckCloseNow()
            if ShouldAbortCurrentActionForResume()
                return false
            Send "{WheelDown}"
            Sleep 1
        }
        Sleep 100
        CheckCloseNow()
        if ShouldAbortCurrentActionForResume()
            return false
        Click
        Sleep 50
    }

    for point in [[1250, 900], [1090, 1020], [811, 540], [960, 710]] {
        CheckCloseNow()
        if ShouldAbortCurrentActionForResume()
            return false
        MouseMove ScaleX(point[1]), ScaleY(point[2]), 2
        Sleep 100
        CheckCloseNow()
        if ShouldAbortCurrentActionForResume()
            return false
        Click
        Sleep 100
    }

    MouseMove whiteRestX, whiteRestY, 2
    return true
}

; ============================================================
; DISCONNECT / RECONNECT
; ============================================================

CheckForDisconnect() {

    global restartImage
    global restartInProgress

    CheckCloseNow()

    if restartInProgress
        return false

    if !FileExist(restartImage)
        return false

    ; Saved reconnect search area:
    ; Left 750, Top 420, Right 1170, Bottom 700.
    ; Scale the coordinates for supported lower resolutions.
    if ImageSearch(
        &restartFoundX,
        &restartFoundY,
        ScaleX(750),
        ScaleY(420),
        ScaleX(1170),
        ScaleY(700),
        restartImage
    ) {
        ReconnectAfterDisconnect()
        return true
    }

    return false
}


MaybeCheckForDisconnect(&lastDisconnectCheck, intervalMs := 10000) {

    if (
        lastDisconnectCheck != 0
        && A_TickCount - lastDisconnectCheck < intervalMs
    )
        return false

    lastDisconnectCheck := A_TickCount
    return CheckForDisconnect()
}

ReconnectAfterDisconnect() {

    global restartInProgress
    global autoClicking

    global playCalibratedColor

    global selectedIsland
    global selectedChallenge
    global selectedDifficulty

    global islandDropdown
    global challengeDropdown
    global difficultyDropdown

    global choiceGui
    global choiceGuiX
    global choiceGuiY

    restartInProgress := true
    autoClicking := false

    SetTimer CheckDeath, 0

    if IsObject(choiceGui)
        choiceGui.Hide()

    playX := ScaleX(932)
    playY := ScaleY(1010)

    playTriggerColor := (
        playCalibratedColor != ""
        ? Integer(playCalibratedColor)
        : 0xDEF5DE
    )

    reconnectSucceeded := false
    maxAttempts := 3
    playTimeoutMs := 30000

    Loop maxAttempts {

        CheckCloseNow()
        attempt := A_Index

        ResetChoiceGui(
            "Reconnect attempt "
            . attempt
            . "/"
            . maxAttempts
            . "..."
        )

        ; Smooth reconnect double-click.
        MouseMove ScaleX(1050), ScaleY(630), 2
        Sleep 250
        Click
        Sleep 100
        Click

        ; Give Roblox time to leave the reconnect screen.
        Sleep 3000

        ResetChoiceGui(
            "Reconnect "
            . attempt
            . "/"
            . maxAttempts
            . " - waiting up to 30s for Play"
        )

        if WaitForPixelColor(
            playX,
            playY,
            playTriggerColor,
            playTimeoutMs,
            100
        ) {
            reconnectSucceeded := true
            break
        }

        ResetChoiceGui(
            "Play timeout on reconnect "
            . attempt
            . "/"
            . maxAttempts
            . " - retrying..."
        )

        Sleep 1000
    }

    if !reconnectSucceeded {

        ; Never leave the farm trapped in restartInProgress.
        ; The normal farm loop can see restart.png again and make
        ; another bounded reconnect attempt later.
        restartInProgress := false
        autoClicking := false

        ResetChoiceGui(
            "Reconnect timed out after 3 attempts - will retry..."
        )

        if IsObject(choiceGui)
            choiceGui.Show("x" choiceGuiX " y" choiceGuiY)

        SetTimer CheckDeath, 2000
        return false
    }

    ; Fresh game: use the current GUI selections.
    selectedIsland := islandDropdown.Text
    selectedChallenge := challengeDropdown.Text
    selectedDifficulty := difficultyDropdown.Text

    SaveSelections()
    ResetSelectionCounts()
    ResetLifeActionCounts()

    ResetChoiceGui("Play detected - restarting starting sequence...")

    StartGame()

    restartInProgress := false
    autoClicking := false

    if IsObject(choiceGui)
        choiceGui.Show("x" choiceGuiX " y" choiceGuiY)

    SetTimer CheckDeath, 2000
    return true
}


; ============================================================
; FARM
; ============================================================

RunFarm() {

    global whiteDetectX
    global whiteDetectY
    global whiteRestX
    global whiteRestY
    global restartInProgress
    global autoClicking
    global sessionDefaultTolerance
    global choiceGui
    global choiceGuiX
    global choiceGuiY
    global resumeToWhiteRequested

    ; restart.png is an ImageSearch, so keep it infrequent.
    ; First check is immediate; later checks are at most every 10 seconds.
    lastDisconnectCheck := 0
    consecutiveRescans := 0

    if IsPlayColorDetected() {
        StartGame()
    }
    else {
        ResetChoiceGui("Play not detected - starting from current game...")
        MouseMove whiteRestX, whiteRestY, 2
    }

    choiceGui.Show("x" choiceGuiX " y" choiceGuiY)

    MouseMove whiteRestX, whiteRestY, 2
    Sleep 100
    Click
    Sleep 50

    Loop {

        CheckCloseNow()

        if ConsumeResumeToWhiteRequest()
            ResetChoiceGui("Resumed - checking for white...")
        else
            ResetChoiceGui()

        if MaybeCheckForDisconnect(&lastDisconnectCheck, 10000)
            continue

        autoClicking := true
        didReconnect := false

        while !restartInProgress {

            CheckCloseNow()

            if ConsumeResumeToWhiteRequest()
                ResetChoiceGui("Resumed - checking for white...")

            if MaybeCheckForDisconnect(&lastDisconnectCheck, 10000) {
                autoClicking := false
                didReconnect := true
                break
            }

            currentWhiteColor := PixelGetColor(
                whiteDetectX,
                whiteDetectY,
                "RGB"
            )

            if IsChoiceWhiteColor(currentWhiteColor) {
                autoClicking := false
                break
            }

            Click whiteRestX, whiteRestY
            Sleep 30
        }

        if didReconnect
            continue

        if restartInProgress {

            autoClicking := false

            while restartInProgress {
                CheckCloseNow()
                Sleep 50
            }

            continue
        }

        autoClicking := false

        ; Keep the requested stable-card delay.
        Sleep 350
        CheckCloseNow()

        if ConsumeResumeToWhiteRequest()
            continue

        if MaybeCheckForDisconnect(&lastDisconnectCheck, 10000)
            continue

        try {

            ResetChoiceGui("White detected - scanning choices...")

            recoveryMode := consecutiveRescans >= 5

            scanResult := ScanVisibleChoices(
                true,
                true,
                recoveryMode
            )

            CheckCloseNow()

            if ConsumeResumeToWhiteRequest() {
                ResetChoiceGui("Resumed - checking for white...")
                continue
            }

            ; If the scan itself took long enough to cross the 10-second
            ; reconnect interval, this performs one reconnect check here.
            if MaybeCheckForDisconnect(&lastDisconnectCheck, 10000)
                continue

            if (
                scanResult.Has("Action")
                && scanResult["Action"] = "rescan"
            ) {

                rescanReason := scanResult.Has("RescanReason")
                    ? scanResult["RescanReason"]
                    : "Screen unclear"

                consecutiveRescans += 1

                if consecutiveRescans >= 6 {
                    ResetChoiceGui(rescanReason " - recovery retry " consecutiveRescans)
                    MouseMove whiteRestX, whiteRestY, 2
                    Sleep 400
                }
                else {
                    ResetChoiceGui(rescanReason " - rescanning...")
                    MouseMove whiteRestX, whiteRestY, 2
                    Sleep 75
                }

                continue
            }

            consecutiveRescans := 0

            if ConsumeResumeToWhiteRequest()
                continue

            if (
                scanResult.Has("Action")
                && scanResult["Action"] = "reroll"
            ) {
                ResetChoiceGui("Rerolled - waiting for refreshed choices...")
                MouseMove whiteRestX, whiteRestY, 2
                Click whiteRestX, whiteRestY
                Sleep 200
                continue
            }

            if (
                scanResult.Has("Banish")
                && IsObject(scanResult["Banish"])
            ) {

                banishResult := scanResult["Banish"]

                CheckCloseNow()
                if ConsumeResumeToWhiteRequest()
                    continue

                if PerformBanishChoice(banishResult) {

                    if MaybeCheckForDisconnect(&lastDisconnectCheck, 10000)
                        continue

                    ResetChoiceGui(
                        "Banished "
                        . banishResult["Name"]
                        . " - waiting for refreshed choices..."
                    )

                    MouseMove whiteRestX, whiteRestY, 2
                    Sleep 200
                    continue
                }
            }

            if (
                scanResult.Has("CanChoose")
                && scanResult["CanChoose"]
                && scanResult.Has("Best")
            ) {

                bestResult := scanResult["Best"]

                CheckCloseNow()
                if ConsumeResumeToWhiteRequest()
                    continue

                targetX := bestResult["X"] + ScaleX(70)
                targetY := bestResult["Y"] + ScaleY(70)

                Sleep 200
                CheckCloseNow()
                if ConsumeResumeToWhiteRequest()
                    continue

                MouseMove targetX, targetY, 2
                Click

                RegisterChoiceSelection(bestResult)

                Sleep 100

                ResetChoiceGui(
                    "Choice made - waiting for white at "
                    . whiteDetectX
                    . ", "
                    . whiteDetectY
                    . "..."
                )

                MouseMove whiteRestX, whiteRestY, 2
            }
            else {
                ResetChoiceGui("No safe choice - waiting for a fresh scan...")
                MouseMove whiteRestX, whiteRestY, 2
            }

            Sleep 50

            MaybeCheckForDisconnect(&lastDisconnectCheck, 10000)

        } catch Error as e {

            autoClicking := false

            SetTimer CheckDeath, 0
            BlockInput "MouseMoveOff"

            MsgBox "Error:`n`n" e.Message
            ExitApp
        }
    }
}

; ============================================================
; DEATH CHECK
; ============================================================

CheckDeath() {

    global restartInProgress
    global autoClicking
    global giveUpCalibratedColor

    if restartInProgress
        return

    deathColor := PixelGetColor(
        ScaleX(1074),
        ScaleY(1030),
        "RGB"
    ) & 0xFFFFFF

    ; Use the calibrated Give Up color as the death trigger.
    ; Keep the old value only as a fallback if Give Up has not
    ; been calibrated/saved yet.
    giveUpTriggerColor := (
        giveUpCalibratedColor != ""
        ? Integer(giveUpCalibratedColor)
        : 0xFEC5C5
    )

    if deathColor = giveUpTriggerColor {
        autoClicking := false
        RestartAfterDeath()
    }
}

; ============================================================
; RESTART AFTER DEATH
; ============================================================

RestartAfterDeath() {

    global whiteRestX
    global whiteRestY
    global restartInProgress
    global autoClicking

    global giveUpCalibratedColor
    global playAgainCalibratedColor

    restartInProgress := true
    autoClicking := false

    ; Death starts a fresh life.
    ResetSelectionCounts()
    ResetLifeActionCounts()

    SetTimer CheckDeath, 0

    giveUpTriggerColor := (
        giveUpCalibratedColor != ""
        ? Integer(giveUpCalibratedColor)
        : 0xFEC5C5
    )

    playAgainTriggerColor := (
        playAgainCalibratedColor != ""
        ? Integer(playAgainCalibratedColor)
        : 0xE3FDE2
    )

    giveUpSampleX := ScaleX(1074)
    giveUpSampleY := ScaleY(1030)

    giveUpClickX := ScaleX(1100)
    giveUpClickY := ScaleY(1010)

    playAgainSampleX := ScaleX(964)
    playAgainSampleY := ScaleY(1020)

    playAgainClickX := ScaleX(960)
    playAgainClickY := ScaleY(1000)

    restartSucceeded := false
    maxAttempts := 3
    playAgainAppearTimeoutMs := 20000

    Loop maxAttempts {

        CheckCloseNow()
        attempt := A_Index

        ResetChoiceGui(
            "Death restart "
            . attempt
            . "/"
            . maxAttempts
            . "..."
        )

        ; --------------------------------------------------------
        ; GIVE UP SAFETY
        ; --------------------------------------------------------
        ; If Give Up is still visible, click it and refuse to continue
        ; until its calibrated color disappears.
        ;
        ; If it remains visible for 10 seconds, click it again.
        ; Up to 3 guarded clicks are made during this restart attempt.
        giveUpColorNow := PixelGetColor(
            giveUpSampleX,
            giveUpSampleY,
            "RGB"
        ) & 0xFFFFFF

        if giveUpColorNow = giveUpTriggerColor {

            giveUpGone := ClickUntilPixelColorGone(
                giveUpSampleX,
                giveUpSampleY,
                giveUpTriggerColor,
                giveUpClickX,
                giveUpClickY,
                10000,
                3,
                "Give Up"
            )

            if !giveUpGone {

                ResetChoiceGui(
                    "Give Up stayed visible - retrying death restart..."
                )

                Sleep 1000
                continue
            }

            ; Preserve the old follow-up confirmation click,
            ; but only AFTER Give Up has definitely disappeared.
            Sleep 3000

            MouseMove giveUpClickX, giveUpClickY, 2
            Sleep 300
            Click
        }

        ; --------------------------------------------------------
        ; WAIT FOR PLAY AGAIN TO APPEAR
        ; --------------------------------------------------------

        ResetChoiceGui(
            "Death restart "
            . attempt
            . "/"
            . maxAttempts
            . " - waiting up to 20s for Play Again"
        )

        if !WaitForPixelColor(
            playAgainSampleX,
            playAgainSampleY,
            playAgainTriggerColor,
            playAgainAppearTimeoutMs,
            50
        ) {

            ResetChoiceGui(
                "Play Again did not appear - retrying..."
            )

            Sleep 1000
            continue
        }

        ; --------------------------------------------------------
        ; PLAY AGAIN SAFETY
        ; --------------------------------------------------------
        ; Once Play Again is detected, click it and DO NOT resume
        ; farming until that calibrated color has disappeared.
        ;
        ; If it is still visible after 10 seconds, click it again.
        playAgainGone := ClickUntilPixelColorGone(
            playAgainSampleX,
            playAgainSampleY,
            playAgainTriggerColor,
            playAgainClickX,
            playAgainClickY,
            10000,
            3,
            "Play Again"
        )

        if !playAgainGone {

            ResetChoiceGui(
                "Play Again stayed visible - retrying restart..."
            )

            Sleep 1000
            continue
        }

        restartSucceeded := true
        break
    }

    if !restartSucceeded {

        ; Keep the previous bounded-retry protection.
        ; Never remain trapped forever in restartInProgress.
        restartInProgress := false
        autoClicking := false

        ResetChoiceGui(
            "Death restart failed after safety retries - will retry..."
        )

        MouseMove whiteRestX, whiteRestY, 2
        SetTimer CheckDeath, 2000
        return false
    }

    ; Both Give Up and Play Again are confirmed gone.
    ; It is now safe to return to the normal farm loop.
    MouseMove whiteRestX, whiteRestY, 2
    Sleep 300

    restartInProgress := false
    autoClicking := false

    SetTimer CheckDeath, 2000
    return true
}

