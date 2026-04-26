; ============================================================
; Horsey Game Save Manager — AHK v2
; ============================================================
#Requires AutoHotkey v2.0
#SingleInstance Force

; ---------- Global variables ----------
global GameRoot := ""
global SaveDir := ""               ; full path to <game>\save
global GameExe := ""               ; full path to the game's executable
global SlotFolders := []            ; slot1 … slot5 paths
global SlotLabels := []             ; custom labels for each slot
global SlotAutosave := []           ; autosave flag (1/0) for each slot
global ActiveSlot := 0              ; currently loaded slot (0 = none)
global IsPlaying := false           ; game session in progress
global GamePID := 0                 ; PID of the running game
global MyGui := ""

; ---------- 1. Locate the game’s save folder ----------
FindRootDir() {
    steamPath := RegRead("HKEY_CURRENT_USER\Software\Valve\Steam", "SteamPath")
    if !steamPath {
        MsgBox "Could not find Steam installation path in registry.", "Error", 16
        ExitApp
    }
    libVdfFile := steamPath "\steamapps\libraryfolders.vdf"
    if !FileExist(libVdfFile) {
        MsgBox "libraryfolders.vdf not found: " libVdfFile, "Error", 16
        ExitApp
    }
    vdfText := FileRead(libVdfFile)
    foundPath := ""
    pos := 1
    while pos := RegExMatch(vdfText, 's)"(\d+)"\s*(\{(?:[^{}]++|(?2))*\})', &lib, pos) {
        fullBlock := lib[2]
        if RegExMatch(fullBlock, 's)"path"\s*"([^"]+)"', &pathM) {
            libPath := StrReplace(pathM[1], "\\", "\")
            if InStr(fullBlock, '"3602570"') {
                foundPath := libPath
                break
            }
        }
        pos += lib.Len[0]
    }
    if !foundPath {
        MsgBox "AppID 3602570 (Horsey Game) not found in any Steam library.", "Error", 16
        ExitApp
    }
    rootDir := foundPath "\steamapps\common\Horsey Game"
    if !DirExist(rootDir) {
        MsgBox "Root directory not found:`n" rootDir, "Error", 16
        ExitApp
    }
    return rootDir
}

; ---------- 2. Initialise folders, game executable, and slot settings ----------
Initialize() {
    global GameRoot, SaveDir, GameExe, SlotFolders, SlotLabels, SlotAutosave

    ; Find the game executable
    exeCandidate := GameRoot "\Horsey.exe"
    if FileExist(exeCandidate)
        GameExe := exeCandidate
    else {
        Loop Files GameRoot "\*.exe" {
            if !InStr(A_LoopFileName, "unins") && !InStr(A_LoopFileName, "UnityCrashHandler") {
                GameExe := A_LoopFileFullPath
                break
            }
        }
    }

    ; Create slot folders if they don’t exist
    SlotFolders := []
    loop 5 {
        folder := SaveDir "\slot" A_Index
        DirCreate folder
        SlotFolders.Push(folder)
    }

    ; Load or create slot settings INI
    LoadSettings()
}

LoadSettings() {
    global SaveDir, SlotLabels, SlotAutosave
    iniFile := SaveDir "\Horsey Game Save Manager.ini"
    SlotLabels := []
    SlotAutosave := []
    loop 5 {
        section := "Slot" A_Index
        label := IniRead(iniFile, section, "Label", "")
        if (label = "")
            label := "Slot " A_Index
        SlotLabels.Push(label)
        autosave := IniRead(iniFile, section, "Autosave", 1)
        SlotAutosave.Push(autosave)
    }
}

SaveSlotSettings(slotNum) {
    global SaveDir, SlotLabels, SlotAutosave
    iniFile := SaveDir "\Horsey Game Save Manager.ini"
    section := "Slot" slotNum
    IniWrite SlotLabels[slotNum], iniFile, section, "Label"
    IniWrite SlotAutosave[slotNum], iniFile, section, "Autosave"
}

; ---------- 3. Main GUI ----------
BuildGui() {
    global MyGui
    MyGui := Gui("+Resize", "Horsey Game Save Manager")
    MyGui.SetFont("s10", "Segoe UI")

    ; ----- Slot rows (1..5) -----
    MyGui.Add("Text", "xm", "Save Slots:").SetFont("bold")
    global SlotStatus := [], PlayBtn := [], SaveBtn := [], DelBtn := [], SettingsBtn := []
    loop 5 {
        slotNum := A_Index
		
		if(SlotAutoSave[slotNum]){
			slotLabelFull := SlotLabels[slotNum] " [autosave]"
		}else{
			slotLabelFull := SlotLabels[slotNum]
		}
        gb := MyGui.Add("GroupBox", "xm w540 h55 Section", slotLabelFull)
        SlotStatus.Push(MyGui.Add("Text", "xs+10 yp+25 w200", "No save yet"))
        PlayBtn.Push(MyGui.Add("Button", "x+20 yp-4 w100 Default", "Play Slot" . slotNum))
        SaveBtn.Push(MyGui.Add("Button", "x+10 yp w100", "Save to Slot"))
        DelBtn.Push(MyGui.Add("Button", "x+10 yp w34", "X"))
        SettingsBtn.Push(MyGui.Add("Button", "x+10 yp w34", "..."))
        ; Bind events
        PlayBtn[slotNum].OnEvent("Click", PlaySlot.Bind(slotNum))
        SaveBtn[slotNum].OnEvent("Click", SaveToSlot.Bind(slotNum))
        DelBtn[slotNum].OnEvent("Click", DeleteSlot.Bind(slotNum))
        SettingsBtn[slotNum].OnEvent("Click", OpenSlotSettings.Bind(slotNum))
    }

    ; Save file status
    global SaveStatus := MyGui.Add("Text", "xm+8 yp+50 w200", "No save yet")
    SaveStatus.SetFont("bold")
    MyGui.Add("Button", "x+20 yp-4 w212", "Play Current Save").OnEvent("Click", PlayCurrent)

    ; StatusBar
    global StatusBar := MyGui.Add("StatusBar",, "Ready")

	
    MyGui.Show()
    UpdateAllStatus()
}

; ---------- 4. Status update functions ----------
UpdateSlotStatus(slotNum) {
    slotFile := SlotFolders[slotNum] "\save1.dat"
    if FileExist(slotFile) {
        time := FileGetTime(slotFile)
        timeStr := FormatTime(time, "yyyy-MM-dd HH:mm")
        SlotStatus[slotNum].Value := "Last save: " . timeStr
    } else {
        SlotStatus[slotNum].Value := "Empty"
    }
}

UpdateSaveStatus() {
    saveFile := SaveDir "\save1.dat"
    if FileExist(saveFile) {
        time := FileGetTime(saveFile)
        timeStr := FormatTime(time, "yyyy-MM-dd HH:mm")
        SaveStatus.Value := "Last Save: " timeStr
    } else {
        SaveStatus.Value := "No Save"
    }
}

UpdateAllStatus() {
    loop 5
        UpdateSlotStatus(A_Index)
    UpdateSaveStatus()
}

; ---------- 5. Button handlers ----------
PlaySlot(slotNum, *) {
    global IsPlaying, ActiveSlot
    critical("On")
    if IsPlaying {
        MsgBox "Game is already running.", "Info", 48
        return
    }
    slotFolder := SlotFolders[slotNum]
    mainSave := SaveDir "\save1.dat"
    mainBackup := SaveDir "\save1_bak.dat"
    slotSave := slotFolder "\save1.dat"
    slotBackup := slotFolder "\save1_bak.dat"

    if FileExist(mainSave) {
        FileMove mainSave, mainBackup, 1
    }
    if FileExist(slotSave) {
        FileCopy slotSave, mainSave
    } else {
        if MsgBox("Slot " . slotNum . " (" . SlotLabels[slotNum] . ") is empty. Game will start with no save data?`r`nIt will use your last cloud save if cloud save is on.", "Confirm", 4) = "Yes" {
            if FileExist(mainSave)
                FileDelete mainSave
        } else {
            return
        }
    }
    ActiveSlot := slotNum
    IsPlaying := true
    DisableControls()
    StatusBar.Text := "Launching game for " . SlotLabels[slotNum] . "..."
    LaunchGame()
}

SaveToSlot(slotNum, *) {
    if MsgBox("Overwrite all data in slot " . slotNum . " (" . SlotLabels[slotNum] . ")?", "Confirm", 4) = "Yes" {
        mainSave := SaveDir "\save1.dat"
        slotFolder := SlotFolders[slotNum]
        slotSave := slotFolder "\save1.dat"
        slotBackup := slotFolder "\save1_bak.dat"
        if !FileExist(mainSave) {
            MsgBox "No current save file (save1.dat) found.", "Error", 48
            return
        }
        if FileExist(slotSave) {
            FileMove slotSave, slotBackup, 1
        }
        FileCopy mainSave, slotSave
        UpdateSlotStatus(slotNum)
        StatusBar.Text := "Current save copied to " . SlotLabels[slotNum]
    }
}

DeleteSlot(slotNum, *) {
    if MsgBox("Delete all data in slot " . slotNum . " (" . SlotLabels[slotNum] . ")?", "Confirm", 4) = "Yes" {
        slotFolder := SlotFolders[slotNum]
        if FileExist(slotFolder "\save1.dat")
            FileDelete slotFolder "\save1.dat"
        if FileExist(slotFolder "\save1_bak.dat")
            FileDelete slotFolder "\save1_bak.dat"
        UpdateSlotStatus(slotNum)
        StatusBar.Text := SlotLabels[slotNum] . " cleared"
    }
}

; --- Settings GUI ---
OpenSlotSettings(slotNum, *) {
    global SlotLabels, SlotAutosave, MyGui
    ; Create a modal child window
    settingsGui := Gui("+Owner" MyGui.Hwnd  . " -SysMenu", "Settings - " . SlotLabels[slotNum])
    settingsGui.SetFont("s10", "Segoe UI")
    settingsGui.Add("Text", "xm", "Slot Label:")
    labelEdit := settingsGui.Add("Edit", "xm w200 vLabel", SlotLabels[slotNum])
    settingsGui.Add("Checkbox", "xm vAutosave Checked" (SlotAutosave[slotNum] ? " Checked" : ""), "Autosave after game ends")
    settingsGui.Add("Button", "xm w80 Default", "OK").OnEvent("Click", SaveSettings)
    settingsGui.Add("Button", "x+10 w80", "Cancel").OnEvent("Click", (*) => (MyGui.Opt("-Disabled"), settingsGui.Destroy()))

    SaveSettings(*) {
        newLabel := labelEdit.Value
        if (newLabel = "")
            newLabel := "Slot " slotNum
        ; Update arrays and INI
        SlotLabels[slotNum] := newLabel
        SlotAutosave[slotNum] := settingsGui["Autosave"].Value ? 1 : 0
        SaveSlotSettings(slotNum)
        ; Update GUI elements for this slot
        ; Find and update the group box and play button text
        ; Since we don't have direct references, we can loop through controls
        ; A simpler approach: destroy the old group box & button, rebuild? Not feasible.
        ; Better to store control handles or use naming. We'll just recreate the whole GUI.
        ; For simplicity, we'll close the settings and refresh the whole main GUI.
        settingsGui.Destroy()
        MyGui.Destroy()
        BuildGui()   ; Full rebuild – easiest and reliable
    }
	
	settingsGui.OnEvent("Close", (*) => (MyGui.Opt("-Disabled"), settingsGui.Destroy()))
	MyGui.Opt("+Disabled")	
    settingsGui.Show()
}

; --- Play with current save ---
PlayCurrent(*) {
    global IsPlaying
    if IsPlaying {
        MsgBox "Game is already running.", "Info", 48
        return
    }
    ActiveSlot := 0
    IsPlaying := true
    DisableControls()
    StatusBar.Text := "Launching game (current save)..."
    LaunchGame()
}

; ---------- 6. Game lifecycle management ----------
LaunchGame() {
    Run "steam://rungameid/3602570"
    SetTimer CheckGameStart, 2000
    SetTimer CheckGameStartTimeout, -30000   ; stop checking after 30s
}

CheckGameStartTimeout() {
    SetTimer CheckGameStart, 0
    if !IsPlaying
        StatusBar.Text := "Game failed to start within 30 seconds."
}

CheckGameStart() {
    if ProcessExist("Horsey.exe") {
        GamePID := ProcessExist("Horsey.exe")
        SetTimer CheckGameStart, 0
        SetTimer CheckGameStartTimeout, 0
        SetTimer CheckGameEnd, 1000
        StatusBar.Text := "Game is running (PID: " . GamePID . ")"
    }
}

CheckGameEnd() {
    global IsPlaying, ActiveSlot
    if !ProcessExist("Horsey.exe") {
        SetTimer CheckGameEnd, 0
        StatusBar.Text := "Game closed – processing"
        Sleep(500)
        PostGame()
        IsPlaying := false
        EnableControls()
        UpdateAllStatus()
        StatusBar.Text := "Ready"
    }
}

PostGame() {
    global ActiveSlot, SlotAutosave
    if (ActiveSlot = 0)
        return
    ; Check autosave flag for the slot
    if !SlotAutosave[ActiveSlot]
        return   ; autosave disabled, do nothing
    slotFolder := SlotFolders[ActiveSlot]
    mainSave := SaveDir "\save1.dat"
    slotSave := slotFolder "\save1.dat"
    slotBackup := slotFolder "\save1_bak.dat"
    if !FileExist(mainSave)
        return
    if FileExist(slotSave)
        FileMove slotSave, slotBackup, 1
    FileCopy mainSave, slotSave
    ActiveSlot := 0
}

; ---------- 7. UI helpers ----------
DisableControls() {
    SetControlState(false)
}
EnableControls() {
    SetControlState(true)
}
SetControlState(enabled) {
    loop 5 {
        PlayBtn[A_Index].Enabled := enabled
        SaveBtn[A_Index].Enabled := enabled
        DelBtn[A_Index].Enabled := enabled
        SettingsBtn[A_Index].Enabled := enabled
    }
}

; ---------- 8. Startup ----------
RootDir := FindRootDir()
SaveDir := RootDir "\save"
Initialize()
BuildGui()

MyGui.OnEvent("Close", (*) => ExitApp())
OnExit ExitFunc
ExitFunc(*) {
    global IsPlaying
    if IsPlaying {
        MsgBox "The game may still be running. Please close it manually.", "Warning", 48
    }
}