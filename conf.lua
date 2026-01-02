-- LÖVE Configuration
function love.conf(t)
    t.identity = "ClassroomPulse"
    t.version = "11.4"
    
    t.window.title = "Classroom Pulse"
    t.window.width = 800
    t.window.height = 600
    t.window.resizable = true
    t.window.minwidth = 400
    t.window.minheight = 500
    
    t.window.usedpiscale = true
    
    t.modules.joystick = false
    t.modules.physics = false
    t.modules.video = false
end

--[[
DATA STORAGE:

Classes are saved as: class_[timestamp].json
Sessions are saved as: session_[timestamp].json
CSV exports are saved as: export_[name].csv

SAVE DIRECTORY:
- Windows: %APPDATA%\LOVE\ClassroomPulse\
- macOS: ~/Library/Application Support/LOVE/ClassroomPulse/
- Linux: ~/.local/share/love/ClassroomPulse/
- Android: /data/data/org.love2d.android/files/save/ClassroomPulse/

CLASS TEMPLATE STRUCTURE:
{
    name: "1st Period - Math",
    timestamp: 1234567890,
    students: [{name: "Jayden", id: 1}, ...]
}

SESSION STRUCTURE:
{
    name: "1st Period - Math - 01/15 9:30AM",
    date: "2025-01-15 09:30",
    timestamp: 1234567890,
    class_id: 1234567890,
    students: [...],
    events: [{student_name, timestamp, timestamp_raw, event}, ...]
}
--]]