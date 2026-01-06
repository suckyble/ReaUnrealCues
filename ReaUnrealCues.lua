local script_title = "ReaUnrealCues"

if not reaper.APIExists("ImGui_CreateContext") then
    reaper.ShowMessageBox("Please install 'ReaImGui' via ReaPack.", "Error", 0)
    return
end

local ctx = reaper.ImGui_CreateContext(script_title)
local WINDOW_FLAGS = reaper.ImGui_WindowFlags_None()

-- STATE
local settings = {
    api_key = reaper.GetExtState("ReaCue_Unreal", "API_Key") or "",
    text_input = "Verse, Chorus, Bridge, Outro",
    voice_idx = 0,
    speed = 0.0,
    pitch = 1.0,
    bitrate = 1,
    trim_silence = true,
    trim_ms = 0.5,    -- Start Trim (500ms)
    tail_ms = 0.2,    -- End Trim (200ms)
    spacing = 1
}

local process_state = 0 
local frame_delay_counter = 0

local voices = {
    "Scarlett (US Female)", "Dan (US Male)", "Will (US Male)", "Liv (US Female)", "Amy (UK Female)",
    "Autumn (US F)", "Melody (US F)", "Hannah (US F)", "Emily (US F)", "Ivy (US F)", "Kaitlyn (US F)", "Luna (US F)", "Willow (US F)", "Lauren (US F)", "Sierra (US F)",
    "Noah (US M)", "Jasper (US M)", "Caleb (US M)", "Ronan (US M)", "Ethan (US M)", "Daniel (US M)", "Zane (US M)",
    "Mei (CN F)", "Lian (CN F)", "Ting (CN F)", "Jing (CN F)",
    "Wei (CN M)", "Jian (CN M)", "Hao (CN M)", "Sheng (CN M)",
    "Lucía (ES F)", "Mateo (ES M)", "Javier (ES M)",
    "Élodie (FR F)",
    "Ananya (HI F)", "Priya (HI F)", "Arjun (HI M)", "Rohan (HI M)",
    "Giulia (IT F)", "Luca (IT M)",
    "Camila (PT F)", "Thiago (PT M)", "Rafael (PT M)"
}

local voice_ids = {
    "Scarlett", "Dan", "Will", "Liv", "Amy",
    "Autumn", "Melody", "Hannah", "Emily", "Ivy", "Kaitlyn", "Luna", "Willow", "Lauren", "Sierra",
    "Noah", "Jasper", "Caleb", "Ronan", "Ethan", "Daniel", "Zane",
    "Mei", "Lian", "Ting", "Jing",
    "Wei", "Jian", "Hao", "Sheng",
    "Lucía", "Mateo", "Javier",
    "Élodie",
    "Ananya", "Priya", "Arjun", "Rohan",
    "Giulia", "Luca",
    "Camila", "Thiago", "Rafael"
}

local bitrates = {"192k", "320k"}
local spacing_opts = {"1 Beat", "1 Bar (4 Beats)"}

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

function GenerateCue(text, index, output_folder)
    local voice_id = voice_ids[settings.voice_idx + 1]
    local url = "https://api.v7.unrealspeech.com/stream"
    
    local temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Temp"
    local json_filename = "reacue_" .. tostring(os.time()) .. "_" .. index .. ".json"
    local json_path = temp_dir .. "\\" .. json_filename
    
    local f = io.open(json_path, "w")
    if not f then Msg("Error: Could not create temp JSON."); return nil end
    
    local safe_text = text:gsub('"', '\\"') 
    local json_content = string.format(
        '{"Text": "%s", "VoiceId": "%s", "Bitrate": "%s", "Speed": "%.2f", "Pitch": "%.2f", "Codec": "libmp3lame"}',
        safe_text, voice_id, bitrates[settings.bitrate], settings.speed, settings.pitch
    )
    
    f:write(json_content)
    f:close()
    
    local safe_name = text:gsub("[^a-zA-Z0-9%-]", "_")
    local outfile = output_folder .. "\\" .. safe_name .. "_" .. tostring(os.time()) .. "_" .. index .. ".mp3"
    
    local cmd = ""
    local win_json = json_path:gsub("/", "\\")
    local win_out = outfile:gsub("/", "\\")
    
    if GetOS() == "Windows" then
        cmd = 'cmd.exe /C curl -s -X POST "' .. url .. '" -H "Authorization: Bearer ' .. settings.api_key .. '" -H "Content-Type: application/json" -d "@' .. win_json .. '" -o "' .. win_out .. '"'
    else
        cmd = "curl -s -X POST '" .. url .. "' -H 'Authorization: Bearer " .. settings.api_key .. "' -H 'Content-Type: application/json' -d @" .. json_path .. " -o '" .. outfile .. "'"
    end
    
    os.execute(cmd)
    os.remove(json_path)
    
    return outfile
end

function ProcessQueue()
    local track = reaper.GetSelectedTrack(0, 0)
    if not track then reaper.ShowMessageBox("Please select a track first!", "Error", 0); return end
    
    local proj_path = reaper.GetProjectPath()
    if not proj_path or proj_path == "" then
        reaper.ShowMessageBox("Please save your project first so we can create the 'cues' folder.", "Project Not Saved", 0)
        return
    end
    
    local cues_path = proj_path .. "\\cues"
    if GetOS() == "Windows" then
        os.execute('if not exist "' .. cues_path .. '" mkdir "' .. cues_path .. '"')
    else
        os.execute('mkdir -p "' .. cues_path .. '"')
    end
    
    local start_pos = reaper.GetCursorPosition()
    
    -- BUG FIX: TimeMap2_timeToBeats returns multiple values. 
    -- The 4th value is the absolute beats since project start.
    local _, _, _, start_beat_abs = reaper.TimeMap2_timeToBeats(0, start_pos)
    
    local cues = SplitString(settings.text_input, ",")
    local last_item_end_time = start_pos

    reaper.Undo_BeginBlock()
    
    for i, cue_text in ipairs(cues) do
        local output_file = GenerateCue(cue_text, i, cues_path)
        
        if output_file then
            local retries = 0
            while not io.open(output_file, "rb") and retries < 120 do
                local s = os.clock(); while os.clock()-s < 0.05 do end; retries=retries+1
            end
            
            local f = io.open(output_file, "rb")
            local success = false
            if f then
                local size = f:seek("end")
                if size > 1000 then 
                    success = true 
                else
                    f:seek("set")
                    local content = f:read("*all")
                    Msg("Skipping '"..cue_text.."': File too small ("..size.." bytes).")
                end
                f:close()
            else
                Msg("Skipping '"..cue_text.."': Timeout waiting for file.")
            end
            
            if success then
                local target_time = 0
                if i == 1 then
                    target_time = start_pos
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
                
                local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                last_item_end_time = target_time + item_len
            end
        end
    end
    
    reaper.SetEditCurPos(last_item_end_time, true, false)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Generate Cues", -1)
end

function loop()
    reaper.ImGui_SetNextWindowSize(ctx, 450, 600, reaper.ImGui_Cond_FirstUseEver())

    local visible, open = reaper.ImGui_Begin(ctx, script_title, true, WINDOW_FLAGS)
    if visible then
        
        if settings.api_key == "" then
            reaper.ImGui_Text(ctx, "Unreal Speech API Key:")
            reaper.ImGui_SetNextItemWidth(ctx, -1)
            local rv, text = reaper.ImGui_InputText(ctx, "##Key", "", 256)
            if rv then 
                settings.api_key = text 
                SaveKey()
            end
            
            reaper.ImGui_TextDisabled(ctx, "(Get free key at unrealspeech.com)")
        else
            reaper.ImGui_Text(ctx, "Cues (comma separated):")
            local rv, text = reaper.ImGui_InputTextMultiline(ctx, "##text", settings.text_input, -1, 60)
            if rv then settings.text_input = text end
            
            reaper.ImGui_Separator(ctx)
            
            -- UI HELPER
            local function LabelAndControl(label, control_func)
                reaper.ImGui_AlignTextToFramePadding(ctx)
                reaper.ImGui_Text(ctx, label)
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_SetNextItemWidth(ctx, -1)
                control_func()
            end

            -- VOICE
            LabelAndControl("Voice: ", function()
                if reaper.ImGui_BeginCombo(ctx, "##Voice", voices[settings.voice_idx+1]) then
                    for i, v in ipairs(voices) do
                        local is_selected = (settings.voice_idx == i-1)
                        if reaper.ImGui_Selectable(ctx, v, is_selected) then
                            settings.voice_idx = i-1
                            if v:match(" Male") and settings.pitch == 1.0 then settings.pitch = 0.92 end
                            if v:match(" Female") and settings.pitch == 0.92 then settings.pitch = 1.0 end
                        end
                        if is_selected then reaper.ImGui_SetItemDefaultFocus(ctx) end
                    end
                    reaper.ImGui_EndCombo(ctx)
                end
            end)
            
            -- SPEED
            LabelAndControl("Speed: ", function()
                local changed, val = reaper.ImGui_SliderDouble(ctx, "##Speed", settings.speed, -0.5, 0.5, "%.2f")
                if changed then settings.speed = val end
            end)

            -- PITCH
            LabelAndControl("Pitch: ", function()
                local changed, val = reaper.ImGui_SliderDouble(ctx, "##Pitch", settings.pitch, 0.5, 1.5, "%.2f")
                if changed then settings.pitch = val end
            end)

            -- SPACING
            LabelAndControl("Space: ", function()
                if reaper.ImGui_BeginCombo(ctx, "##Spacing", spacing_opts[settings.spacing+1]) then
                    for i, v in ipairs(spacing_opts) do
                        if reaper.ImGui_Selectable(ctx, v, settings.spacing == i-1) then settings.spacing = i-1 end
                    end
                    reaper.ImGui_EndCombo(ctx)
                end
            end)
            
            reaper.ImGui_Separator(ctx)
            
            local changed, val = reaper.ImGui_Checkbox(ctx, "Auto-Trim Silence", settings.trim_silence)
            if changed then settings.trim_silence = val end
            
            if settings.trim_silence then
                -- TRIM START
                LabelAndControl("Start: ", function()
                    local c, v = reaper.ImGui_SliderDouble(ctx, "##start", settings.trim_ms, 0.0, 1.0, "%.2fs")
                    if c then settings.trim_ms = v end
                end)

                -- TRIM TAIL
                LabelAndControl("Tail:  ", function()
                    local c, v = reaper.ImGui_SliderDouble(ctx, "##tail", settings.tail_ms, 0.0, 2.0, "%.2fs")
                    if c then settings.tail_ms = v end
                end)
            end

            reaper.ImGui_Separator(ctx)
            
            local btn_h = 40
            
            if process_state == 0 then
                if reaper.ImGui_Button(ctx, "GENERATE CUES", -1, btn_h) then
                    process_state = 1 -- Start update cycle
                    frame_delay_counter = 0
                end
            else
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xCCCC00FF) -- Yellow
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xCCCC00FF)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xCCCC00FF)
                reaper.ImGui_Button(ctx, "GENERATING... (PLEASE WAIT)", -1, btn_h)
                reaper.ImGui_PopStyleColor(ctx, 3)
            end

            reaper.ImGui_Dummy(ctx, 0, 5)
            if reaper.ImGui_Button(ctx, "Change API Key", -1, 25) then
                ResetKey()
            end
        end
        
        reaper.ImGui_End(ctx)
    end
    
    if open then
        if process_state == 1 then
            frame_delay_counter = frame_delay_counter + 1
            if frame_delay_counter > 2 then
                process_state = 2 -- Ready to run
            end
        elseif process_state == 2 then
            ProcessQueue()
            process_state = 0 -- Reset
        end
        reaper.defer(loop)
    else
        if reaper.ImGui_DestroyContext then
            reaper.ImGui_DestroyContext(ctx)
        end
    end
end

reaper.defer(loop)
