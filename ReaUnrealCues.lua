local script_title = "ReaUnrealCuesv2"

if not reaper.APIExists("ImGui_CreateContext") then
    reaper.ShowMessageBox("Please install 'ReaImGui' via ReaPack.", "Error", 0)
    return
end

local ctx = reaper.ImGui_CreateContext(script_title)
local WINDOW_FLAGS = reaper.ImGui_WindowFlags_None()

-- INITIALIZATION
local default_version = 8
local default_tail = (default_version == 8) and 0.7 or 0.2

-- STATE
local settings = {
    api_key = reaper.GetExtState("ReaCue_Unreal", "API_Key") or "",
    text_input = "Verse, Chorus, Bridge, Outro",
    voice_idx = 0,
    api_version = default_version,
    speed = 0.0,
    pitch = 1.0,
    bitrate = 1,
    trim_silence = true,
    trim_ms = 0.5,
    tail_ms = default_tail,
    spacing = 1
}

local process_state = 0 
local library_files = {} 
local library_path_cache = ""
local need_refresh = true

-- =========================================================
-- VOICE DATA
-- =========================================================

local voices_v7_display = {
    "Scarlett (US Female)", "Dan (US Male)", "Liv (US Female)", "Will (US Male)", "Amy (UK Female)"
}
local voices_v7_ids = {
    "Scarlett", "Dan", "Liv", "Will", "Amy"
}

local voices_v8_display = {
    "Autumn (US)", "Melody (US)", "Hannah (US)", "Emily (US)", "Ivy (US)", "Kaitlyn (US)", "Luna (US)", "Willow (US)", "Lauren (US)", "Sierra (US)",
    "Noah (US)", "Jasper (US)", "Caleb (US)", "Ronan (US)", "Ethan (US)", "Daniel (US)", "Zane (US)",
    "Mei (CN Fem)", "Lian (CN Fem)", "Ting (CN Fem)", "Jing (CN Fem)",
    "Wei (CN Male)", "Jian (CN Male)", "Hao (CN Male)", "Sheng (CN Male)",
    "Lucía (ES Fem)", "Mateo (ES Male)", "Javier (ES Male)",
    "Élodie (FR Fem)",
    "Ananya (HI Fem)", "Priya (HI Fem)", "Arjun (HI Male)", "Rohan (HI Male)",
    "Giulia (IT Fem)", "Luca (IT Male)",
    "Camila (PT Fem)", "Thiago (PT Male)", "Rafael (PT Male)"
}

local voices_v8_ids = {
    "Autumn", "Melody", "Hannah", "Emily", "Ivy", "Kaitlyn", "Luna", "Willow", "Lauren", "Sierra",
    "Noah", "Jasper", "Caleb", "Ronan", "Ethan", "Daniel", "Zane",
    "Mei", "Lian", "Ting", "Jing", "Wei", "Jian", "Hao", "Sheng",
    "Lucía", "Mateo", "Javier",
    "Élodie",
    "Ananya", "Priya", "Arjun", "Rohan",
    "Giulia", "Luca",
    "Camila", "Thiago", "Rafael"
}

local bitrates = {"192k", "320k"}
local spacing_opts = {"1 Beat", "1 Bar (4 Beats)"}

-- UTILS
function Msg(str) reaper.ShowConsoleMsg(tostring(str) .. "\n") end
function GetOS() return reaper.GetOS():match("Win") and "Windows" or "Other" end

function SplitString(inputstr, sep)
    if sep == nil then sep = "%s" end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        local trimmed = str:match("^%s*(.-)%s*$")
        table.insert(t, trimmed)
    end
    return t
end

function SaveKey()
    reaper.SetExtState("ReaCue_Unreal", "API_Key", settings.api_key, true)
end

function ResetKey()
    reaper.DeleteExtState("ReaCue_Unreal", "API_Key", true)
    settings.api_key = ""
end

function GetCurlPath()
    if GetOS() == "Windows" then
        local sys_curl = "C:\\Windows\\System32\\curl.exe"
        if reaper.file_exists(sys_curl) then return sys_curl end
    end
    return "curl"
end

-- --- LIBRARY FUNCTIONS ---

function GetCuesFolderPath()
    local proj_path = reaper.GetProjectPath()
    if not proj_path or proj_path == "" then return nil end
    local sep = (GetOS() == "Windows") and "\\" or "/"
    return proj_path .. sep .. "cues" .. sep
end

function ScanLibrary()
    local path = GetCuesFolderPath()
    if not path then return end
    
    library_files = {}
    local i = 0
    repeat
        local file = reaper.EnumerateFiles(path, i)
        if file then
            if file:match("%.mp3$") or file:match("%.wav$") then
                table.insert(library_files, file)
            end
        end
        i = i + 1
    until not file
    
    table.sort(library_files)
    library_path_cache = path
    need_refresh = false
end

function InsertLibraryItem(filename)
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then reaper.ShowMessageBox("Select a track first!", "Error", 0); return end
    
    local path = library_path_cache .. filename
    local pos = reaper.GetCursorPosition()
    
    reaper.Undo_BeginBlock()
    
    local item = reaper.AddMediaItemToTrack(track)
    local take = reaper.AddTakeToMediaItem(item)
    
    local src = reaper.PCM_Source_CreateFromFile(path)
    reaper.SetMediaItemTake_Source(take, src)
    local src_len, _ = reaper.GetMediaSourceLength(src)
    
    if settings.trim_silence then
        reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", settings.trim_ms)
        local new_len = src_len - settings.trim_ms - settings.tail_ms
        if new_len < 0.1 then new_len = 0.1 end
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
    else
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", src_len)
    end
    
    reaper.SetMediaItemInfo_Value(item, "D_POSITION", pos)
    reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", 16777471|0x1000000)
    
    local clean_name = filename:gsub("%.mp3$", ""):gsub("_%d+$", "") 
    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", clean_name, true)
    
    reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
    reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
    
    reaper.UpdateItemInProject(item)
    
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    reaper.SetEditCurPos(pos + len, true, false)
    
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Insert Cue from Library", -1)
end

-- --- GENERATION ---

-- HELPER: Get OS-Specific Separator
function GetPathSeparator()
    if GetOS() == "Windows" then return "\\" else return "/" end
end

function GenerateCue(text, index, output_folder)
    local current_ids = (settings.api_version == 8) and voices_v8_ids or voices_v7_ids
    local current_display = (settings.api_version == 8) and voices_v8_display or voices_v7_display
    
    local voice_id = current_ids[settings.voice_idx + 1]
    local voice_name_raw = current_display[settings.voice_idx + 1]
    
    local url = "https://api.v" .. settings.api_version .. ".unrealspeech.com/stream"
    
    -- FIX: Cross-platform Temp Directory
    local sep = GetPathSeparator()
    local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or (GetOS() == "Windows" and "C:\\Temp" or "/tmp")
    local json_filename = "reacue_" .. tostring(os.time()) .. "_" .. index .. ".json"
    
    -- FIX: Use correct separator for the OS
    local json_path = temp_dir .. sep .. json_filename
    
    local f = io.open(json_path, "w")
    if not f then Msg("Error: Could not create temp JSON at: " .. json_path); return nil end
    
    local safe_text = text:gsub('"', '\\"') 
    local json_content = string.format(
        '{"Text": "%s", "VoiceId": "%s", "Bitrate": "%s", "Speed": "%.2f", "Pitch": "%.2f", "Codec": "libmp3lame"}',
        safe_text, voice_id, bitrates[settings.bitrate], settings.speed, settings.pitch
    )
    f:write(json_content)
    f:close()
    
    -- SMART FILENAME
    local fn_text = text:gsub("[^a-zA-Z0-9]", "")
    if #fn_text > 15 then fn_text = fn_text:sub(1, 15) end
    if fn_text == "" then fn_text = "Cue" end
    
    local fn_voice = voice_name_raw:match("^(.-) %(") or voice_name_raw:gsub(" ", "")
    fn_voice = fn_voice:gsub("%[.-%]", ""):gsub(" ", "") 
    
    local fn_params = string.format("Sp%.1f_Pi%.1f", settings.speed, settings.pitch)
    local unique_id = tostring(os.time()) .. index
    
    local safe_name = string.format("%s_%s_%s_%s", fn_text, fn_voice, fn_params, unique_id)
    local outfile = output_folder .. safe_name .. ".mp3"
    
    local cmd = ""
    if GetOS() == "Windows" then
        -- Windows: Use ExecProcess with explicit curl path + double quotes
        local win_json = json_path:gsub("/", "\\")
        local win_out = outfile:gsub("/", "\\")
        local curl_exe = GetCurlPath()
        
        cmd = string.format('"%s" -s -X POST "%s" -H "Authorization: Bearer %s" -H "Content-Type: application/json; charset=utf-8" -d "@%s" -o "%s"', 
            curl_exe, url, settings.api_key, win_json, win_out)
    else
        -- Mac/Linux: Standard curl is usually in PATH, works with simple string
        cmd = string.format('curl -s -X POST "%s" -H "Authorization: Bearer %s" -H "Content-Type: application/json; charset=utf-8" -d "@%s" -o "%s"', 
            url, settings.api_key, json_path, outfile)
    end
    
    -- Execute
    local result = reaper.ExecProcess(cmd, 15000)
    os.remove(json_path)
    
    return outfile
end

function ProcessQueue()
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then reaper.ShowMessageBox("Please select a track first!", "Error", 0); return end
    
    local cues_path = GetCuesFolderPath()
    if not cues_path then
        reaper.ShowMessageBox("Please save your project first.", "Project Not Saved", 0)
        return
    end
    
    if GetOS() == "Windows" then
        os.execute('if not exist "' .. cues_path .. '" mkdir "' .. cues_path .. '"')
    else
        os.execute('mkdir -p "' .. cues_path .. '"')
    end
    
    local start_pos = reaper.GetCursorPosition()
    local _, _, _, start_beat_abs = reaper.TimeMap2_timeToBeats(0, start_pos)
    
    local cues = SplitString(settings.text_input, ",")
    
    reaper.Undo_BeginBlock()
    
    for i, cue_text in ipairs(cues) do
        local output_file = GenerateCue(cue_text, i, cues_path)
        
        if output_file then
            local f = io.open(output_file, "rb")
            local success = false
            if f then
                local size = f:seek("end")
                if size > 1000 then success = true else f:seek("set"); local err = f:read("*all"); Msg("API Error: "..tostring(err)) end
                f:close()
            else
                Msg("File Error: Not created.")
            end
            
            if success then
                local target_time = 0
                if i == 1 then target_time = start_pos
                else
                    local beat_step = (settings.spacing == 0) and 1 or 4
                    local target_beat = start_beat_abs + ((i - 1) * beat_step)
                    target_time = reaper.TimeMap2_beatsToTime(0, target_beat)
                end
                
                local item = reaper.AddMediaItemToTrack(track)
                local take = reaper.AddTakeToMediaItem(item)
                
                local src = reaper.PCM_Source_CreateFromFile(output_file)
                reaper.SetMediaItemTake_Source(take, src)
                local src_len, _ = reaper.GetMediaSourceLength(src)
                
                if settings.trim_silence then
                    reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", settings.trim_ms)
                    local new_len = src_len - settings.trim_ms - settings.tail_ms
                    if new_len < 0.1 then new_len = 0.1 end
                    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
                else
                    reaper.SetMediaItemInfo_Value(item, "D_LENGTH", src_len)
                end
                
                reaper.SetMediaItemInfo_Value(item, "D_POSITION", target_time)
                reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", 16777471|0x1000000)
                reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", cue_text, true)
                reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0)
                reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0)
                
                reaper.UpdateItemInProject(item)
                
                local last_item_end = target_time + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                reaper.SetEditCurPos(last_item_end, true, false)
            end
        end
    end
    
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Generate Cues", -1)
    need_refresh = true
end

function loop()
    -- WINDOW SIZE: 850x550
    reaper.ImGui_SetNextWindowSize(ctx, 850, 550, reaper.ImGui_Cond_FirstUseEver())

    local visible, open = reaper.ImGui_Begin(ctx, script_title, true, WINDOW_FLAGS)
    if visible then
        
        if settings.api_key == "" then
            reaper.ImGui_Text(ctx, "Unreal Speech API Key:")
            reaper.ImGui_SetNextItemWidth(ctx, -1)
            local rv, text = reaper.ImGui_InputText(ctx, "##Key", "", 256)
            if rv then settings.api_key = text; SaveKey() end
            reaper.ImGui_TextDisabled(ctx, "(Get free key at unrealspeech.com)")
        else
            local function LabelAndControl(label, control_func)
                reaper.ImGui_AlignTextToFramePadding(ctx)
                reaper.ImGui_Text(ctx, label)
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, -1)
                control_func()
            end

            -- === LEFT COLUMN (GENERATOR) ===
            local border_flags = reaper.ImGui_ChildFlags_Border and reaper.ImGui_ChildFlags_Border() or 1
            
            if reaper.ImGui_BeginChild(ctx, "LeftPane", 400, -1, border_flags) then
                
                reaper.ImGui_Text(ctx, "GENERATOR")
                reaper.ImGui_Separator(ctx)
                
                LabelAndControl("Engine:", function()
                    local current_name = (settings.api_version == 8) and "V8 (Modern)" or "V7 (Legacy)"
                    if reaper.ImGui_BeginCombo(ctx, "##Version", current_name) then
                        if reaper.ImGui_Selectable(ctx, "V7 (Legacy)", settings.api_version == 7) then
                            settings.api_version = 7; settings.voice_idx = 0; settings.tail_ms = 0.2
                        end
                        if reaper.ImGui_Selectable(ctx, "V8 (Modern)", settings.api_version == 8) then
                            settings.api_version = 8; settings.voice_idx = 0; settings.tail_ms = 0.7
                        end
                        reaper.ImGui_EndCombo(ctx)
                    end
                end)

                reaper.ImGui_Text(ctx, "Cues:")
                local rv, text = reaper.ImGui_InputTextMultiline(ctx, "##text", settings.text_input, -1, 150)
                if rv then settings.text_input = text end
                
                reaper.ImGui_Separator(ctx)
                
                local current_voices = (settings.api_version == 8) and voices_v8_display or voices_v7_display
                LabelAndControl("Voice: ", function()
                    if reaper.ImGui_BeginCombo(ctx, "##Voice", current_voices[settings.voice_idx+1]) then
                        for i, v in ipairs(current_voices) do
                            if reaper.ImGui_Selectable(ctx, v, settings.voice_idx == i-1) then settings.voice_idx = i-1 end
                        end
                        reaper.ImGui_EndCombo(ctx)
                    end
                end)
                
                LabelAndControl("Speed: ", function()
                    local c, v = reaper.ImGui_SliderDouble(ctx, "##Speed", settings.speed, -0.5, 0.5, "%.2f")
                    if c then settings.speed = v end
                end)
                LabelAndControl("Pitch: ", function()
                    local c, v = reaper.ImGui_SliderDouble(ctx, "##Pitch", settings.pitch, 0.5, 1.5, "%.2f")
                    if c then settings.pitch = v end
                end)
                LabelAndControl("Space: ", function()
                    if reaper.ImGui_BeginCombo(ctx, "##Spacing", spacing_opts[settings.spacing+1]) then
                        for i, v in ipairs(spacing_opts) do
                            if reaper.ImGui_Selectable(ctx, v, settings.spacing == i-1) then settings.spacing = i-1 end
                        end
                        reaper.ImGui_EndCombo(ctx)
                    end
                end)
                
                reaper.ImGui_Separator(ctx)
                local c, v = reaper.ImGui_Checkbox(ctx, "Auto-Trim", settings.trim_silence)
                if c then settings.trim_silence = v end
                
                if settings.trim_silence then
                    LabelAndControl("Start: ", function()
                        local c, v = reaper.ImGui_SliderDouble(ctx, "##start", settings.trim_ms, 0.0, 1.0, "%.2fs")
                        if c then settings.trim_ms = v end
                    end)
                    LabelAndControl("Tail:  ", function()
                        local c, v = reaper.ImGui_SliderDouble(ctx, "##tail", settings.tail_ms, 0.0, 2.0, "%.2fs")
                        if c then settings.tail_ms = v end
                    end)
                end

                reaper.ImGui_Separator(ctx)
                
                -- GENERATE BUTTON (Visual Fix: 3-Color Push for Yellow)
                if process_state == 0 then
                    if reaper.ImGui_Button(ctx, "GENERATE CUES", -1, 50) then
                        process_state = 1; frame_delay_counter = 0
                    end
                else
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xCCCC00FF)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xCCCC00FF)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xCCCC00FF)
                    reaper.ImGui_Button(ctx, "GENERATING... WAIT", -1, 50)
                    reaper.ImGui_PopStyleColor(ctx, 3)
                end
                
                reaper.ImGui_Dummy(ctx, 0, 10)
                if reaper.ImGui_Button(ctx, "Change API Key", -1, 20) then ResetKey() end
            
                reaper.ImGui_EndChild(ctx)
            end

            reaper.ImGui_SameLine(ctx)

            -- === RIGHT COLUMN (LIBRARY) ===
            if reaper.ImGui_BeginChild(ctx, "RightPane", -1, -1, border_flags) then
                reaper.ImGui_Text(ctx, "CUES LIBRARY")
                reaper.ImGui_SameLine(ctx)
                
                if need_refresh then ScanLibrary() end
                
                local avail = reaper.ImGui_GetContentRegionAvail(ctx)
                reaper.ImGui_SameLine(ctx, reaper.ImGui_GetCursorPosX(ctx) + avail - 120)
                if reaper.ImGui_Button(ctx, "Refresh") then need_refresh = true end
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "Folder") then
                    local path = GetCuesFolderPath()
                    if path then 
                        if GetOS() == "Windows" then os.execute('explorer "'..path..'"') 
                        else os.execute('open "'..path..'"') end
                    end
                end
                
                reaper.ImGui_Separator(ctx)
                
                if #library_files == 0 then
                    reaper.ImGui_TextDisabled(ctx, "No files found in /cues folder.")
                    reaper.ImGui_TextDisabled(ctx, "Generate some cues first!")
                else
                    if reaper.ImGui_BeginChild(ctx, "ScrollingRegion", -1, -1, 0) then
                        for _, file in ipairs(library_files) do
                            reaper.ImGui_AlignTextToFramePadding(ctx)
                            local display_name = file
                            if #display_name > 40 then display_name = display_name:sub(1,37).."..." end
                            reaper.ImGui_Text(ctx, display_name)
                            if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, file) end
                            
                            reaper.ImGui_SameLine(ctx)
                            local w = reaper.ImGui_GetContentRegionAvail(ctx)
                            reaper.ImGui_SameLine(ctx, reaper.ImGui_GetCursorPosX(ctx) + w - 50)
                            
                            if reaper.ImGui_Button(ctx, "Insert##"..file, 50) then
                                InsertLibraryItem(file)
                            end
                        end
                        reaper.ImGui_EndChild(ctx)
                    end
                end
                reaper.ImGui_EndChild(ctx)
            end
        end
        
        reaper.ImGui_End(ctx)
    end
    
    if open then
        if process_state == 1 then
            frame_delay_counter = frame_delay_counter + 1
            if frame_delay_counter > 2 then process_state = 2 end
        elseif process_state == 2 then
            ProcessQueue()
            process_state = 0
        end
        reaper.defer(loop)
    else
        if reaper.ImGui_DestroyContext then reaper.ImGui_DestroyContext(ctx) end
    end
end

reaper.defer(loop)
