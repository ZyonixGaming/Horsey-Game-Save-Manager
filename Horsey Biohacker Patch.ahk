#Requires AutoHotkey v2.0

; ------------------------- GUI -------------------------
MyGui := Gui(, "Patch Configuration")
MyGui.Add("Text",, "Generation count (default 64):")
genCountEdit := MyGui.Add("Edit", "w100", "64")
MyGui.Add("Text",, "Race count (default 64):")
raceCountEdit := MyGui.Add("Edit", "w100", "64")
btnSelect := MyGui.Add("Button", "w150", "Choose EXE to Patch")
MyGui.Show()

btnSelect.OnEvent("Click", StartPatching)

StartPatching(*) {
    global MyGui
    ; Disable GUI controls
    genCountEdit.Enabled := false
    raceCountEdit.Enabled := false
    btnSelect.Enabled := false

    filePath := FileSelect(3, , "Select binary to patch", "Executable Files (*.exe;*.dll;*.bin)")
    if (filePath = "") {
        EnableGuiControls()
        return
    }

    ; Read user counts (values set before clicking)
    genCount := Integer(genCountEdit.Value)
    raceCount := Integer(raceCountEdit.Value)
    genCount := Min(255, Max(0, genCount))
    raceCount := Min(255, Max(0, raceCount))
    genHex := genCount
    raceHex := raceCount

    ; INI file in the same folder as the EXE
    SplitPath(filePath, , &exeDir)
    INI_FILE := exeDir "\horsey_biohacker_patch.ini"

    ; Read the whole binary file (always needed)
    try {
        buf := FileRead(filePath, "RAW")
        if !buf || buf.Size = 0
            throw Error("Empty file")
    } catch {
        MsgBox("Failed to read file.`n" filePath, "Error", "IconX")
        EnableGuiControls()
        return
    }

    ; Helper functions (defined once)
    GetByte(offset) => (offset >= 0 && offset < buf.Size) ? NumGet(buf, offset, "UChar") : -1
    SetByte(offset, value) {
        if (offset < 0 || offset >= buf.Size)
            return false
        NumPut("UChar", value, buf, offset)
        return true
    }

    ; ---------- OPTIMIZED: Try to use saved INI first ----------
    if FileExist(INI_FILE) {
        savedPos := Map()
        loop read, INI_FILE {
            if InStr(A_LoopReadLine, "=") {
                parts := StrSplit(A_LoopReadLine, "=")
                if parts.Length = 2 {
                    key := Trim(parts[1])
                    val := Integer(Trim(parts[2]))
                    savedPos[key] := val
                }
            }
        }

        requiredKeys := ["Offset0","Pos1","Pos2","Pos3","Pos4","Pos5","Pos6"]
        allKeysExist := true
        for k in requiredKeys
            if !savedPos.Has(k) {
                allKeysExist := false
                break
            }

        if allKeysExist {
            ; Quick signature verification (only a few bytes)
            if (GetByte(savedPos["Offset0"] + 5) = 0x62
                && GetByte(savedPos["Pos1"] + 4) = 0x89
                && GetByte(savedPos["Pos1"] + 5) = 0x83
                && GetByte(savedPos["Pos5"] + 4) = 0xC7
                && GetByte(savedPos["Pos5"] + 5) = 0x86) {

                ; ---- Patch using saved positions ----
                ; Patch 1
                patch1_bytes := [0x00,0x00,0x00,0x00,0xEB,0x62]
                for i, byte in patch1_bytes
                    SetByte(savedPos["Offset0"] + i - 1, byte)

                SetByte(savedPos["Pos1"], genHex)
                SetByte(savedPos["Pos2"], genHex)
                SetByte(savedPos["Pos5"], genHex)

                SetByte(savedPos["Pos3"], raceHex)
                SetByte(savedPos["Pos4"], raceHex)
                SetByte(savedPos["Pos6"], raceHex)

                SavePatchedFile(buf, filePath)
                MsgBox("Patching successful! Used previously saved positions (verified).`n"
                       . "Generation count: " genCount " (0x" Format("{:02X}", genHex) ")`n"
                       . "Race count: " raceCount " (0x" Format("{:02X}", raceHex) ")",
                       "Success", "IconI")
                ExitApp()
            }
        }
    }

    ; ---------- Fresh search (only if INI missing or invalid) ----------
    FindPattern(buf, pattern, startOff := 0) {
        buflen := buf.Size
        patlen := pattern.Length
        loop buflen - patlen + 1 - startOff {
            offset := startOff + A_Index - 1
            match := true
            loop patlen {
                if NumGet(buf, offset + A_Index - 1, "UChar") != pattern[A_Index] {
                    match := false
                    break
                }
            }
            if match
                return offset
        }
        return -1
    }

    pos := Map()
    p1_offset := FindPattern(buf, [0x2C,0x01,0x00,0x00,0x7D,0x62])
    if (p1_offset >= 0)
        pos["Offset0"] := p1_offset

    p2_offset := FindPattern(buf, [0x10,0x00,0x00,0x00,0x89,0x83])
    if (p2_offset >= 0) {
        pos["Pos1"] := p2_offset
        pos["Pos2"] := p2_offset + 11
        pos["Pos3"] := pos["Pos2"] + 8
        pos["Pos4"] := pos["Pos3"] + 11
    }

    p3_offset := FindPattern(buf, [0x10,0x00,0x00,0x00,0xC7,0x86])
    if (p3_offset >= 0) {
        pos["Pos5"] := p3_offset
        pos["Pos6"] := p3_offset + 10
    }

    requiredKeys := ["Offset0","Pos1","Pos2","Pos3","Pos4","Pos5","Pos6"]
    allFound := true
    for k in requiredKeys
        if !pos.Has(k) {
            allFound := false
            break
        }

    if !allFound {
        MsgBox("Could not locate all required patterns, and no valid saved positions file found.`n"
               . "File not recognized.", "Error", "IconX")
        EnableGuiControls()
        ExitApp()
    }

    ; ---- Fresh patch (first time) ----
    patch1_bytes := [0x00,0x00,0x00,0x00,0xEB,0x62]
    for i, byte in patch1_bytes
        SetByte(pos["Offset0"] + i - 1, byte)

    SetByte(pos["Pos1"], genHex)
    SetByte(pos["Pos2"], genHex)
    SetByte(pos["Pos5"], genHex)

    SetByte(pos["Pos3"], raceHex)
    SetByte(pos["Pos4"], raceHex)
    SetByte(pos["Pos6"], raceHex)

    ; Save positions to INI
    iniContent := "[Positions]`n"
    for k, v in pos
        iniContent .= k "=" v "`n"
    try {
        if FileExist(INI_FILE)
            FileDelete(INI_FILE)
        FileAppend(iniContent, INI_FILE)
    } catch{
	}

    SavePatchedFile(buf, filePath)
    MsgBox("Patching successful! All positions found and updated.`n"
           . "Generation count: " genCount " (0x" Format("{:02X}", genHex) ")`n"
           . "Race count: " raceCount " (0x" Format("{:02X}", raceHex) ")",
           "Success", "IconI")
    ExitApp()
}

SavePatchedFile(buf, originalPath) {
    global MyGui
    MyGui.Hide()
    ;outputPath := FileSelect("S", , "Save patched file as", "Executable Files (*.exe;*.dll;*.bin)")
	outputPath := originalPath
    if (outputPath = "") {
        MyGui.Show()
        throw Error("No output file selected")
    }
    outFile := FileOpen(outputPath, "w")
    if !outFile {
        MyGui.Show()
        throw Error("Cannot create output file")
    }
    outFile.RawWrite(buf, buf.Size)
    outFile.Close()
    MyGui.Show()
}

EnableGuiControls() {
    global genCountEdit, raceCountEdit, btnSelect
    genCountEdit.Enabled := true
    raceCountEdit.Enabled := true
    btnSelect.Enabled := true
}