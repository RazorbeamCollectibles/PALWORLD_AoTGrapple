-- AoTGrapple - UE4SS Lua mod for Palworld.

local UEHelpers = require("UEHelpers")

local MOD_NAME = "AoTGrapple"
local AUDIO_SERVERS = {
    [[ue4ss\Mods\AoTGrapple\audio_server.ps1]],
    [[Mods\AoTGrapple\audio_server.ps1]],
}
local QUIT_HELPERS = {
    [[ue4ss\Mods\AoTGrapple\quit.ps1]],
    [[Mods\AoTGrapple\quit.ps1]],
}
local STATE_DIR = os.getenv("TEMP") .. [[\AoTGrapple]]
local COMMAND_FILE = STATE_DIR .. [[\command.txt]]

local MISS_TIMEOUT_MS = 900
local GRAPPLE_END_GLIDER_GRACE_MS = 500
local GLIDER_POLL_MS = 100
local GRAPPLE_STATE_POLL_MS = 100
local GRAPPLE_STATE_POLL_LIMIT = 300
local MIN_GLIDER_SPEED = 80.0
local MIN_INTERVAL_SECONDS = 0.35

local HOOKS = {
    { path = "/Script/Pal.PalGrapplingGunModule:ShotCable", action = "shot" },
    { path = "/Script/Pal.PalGrapplingGunModule:OnStartAction", action = "confirm" },
    { path = "/Script/Pal.PalGrapplingGunModule:OnStartGrapplingAction", action = "confirm" },
    { path = "/Script/Pal.PalGrapplingGunModule:OnEndGrapplingAction", action = "grapple_end" },
    { path = "/Script/Pal.PalGrapplingGunModule:OnDetachWeapon", action = "grapple_end" },
    { path = "/Script/Pal.PalGrapplingGunModule:InterruptAction", action = "stop" },
}

local last_play = 0
local shot_id = 0
local confirmed_shot_id = 0
local audio_active = false
local active_monitor_id = 0
local active_grapple_module = nil

local function log(message)
    print(string.format("[%s] %s\n", MOD_NAME, message))
end

local function get_player()
    local ok, player = pcall(UEHelpers.GetPlayer)
    if ok and player and player.IsValid and player:IsValid() then
        return player
    end
    return nil
end

local function is_player_gliding()
    local player = get_player()
    if not player or not player.IsGliding then
        return false
    end

    local ok, result = pcall(function()
        return player:IsGliding()
    end)
    return ok and result == true
end

local function is_player_climbing()
    local player = get_player()
    if not player then
        return false
    end

    if player.IsClimbing then
        local ok, result = pcall(function()
            return player:IsClimbing()
        end)
        if ok and result == true then
            return true
        end
    end

    if player.CharacterMovement and player.CharacterMovement.IsClimbing then
        local ok, result = pcall(function()
            return player.CharacterMovement:IsClimbing()
        end)
        return ok and result == true
    end

    return false
end

local function is_player_grounded()
    local player = get_player()
    if not player or not player.CharacterMovement then
        return false
    end

    if player.CharacterMovement.IsMovingOnGround then
        local ok, result = pcall(function()
            return player.CharacterMovement:IsMovingOnGround()
        end)
        if ok and result == true then
            return true
        end
    end

    if player.CharacterMovement.IsFalling then
        local ok, result = pcall(function()
            return player.CharacterMovement:IsFalling()
        end)
        if ok then
            return result ~= true
        end
    end

    return false
end

local function is_player_moving_fast_enough()
    local player = get_player()
    if not player or not player.GetVelocity then
        return false
    end

    local ok, velocity = pcall(function()
        return player:GetVelocity()
    end)
    if not ok or not velocity then
        return false
    end

    local x = velocity.X or 0.0
    local y = velocity.Y or 0.0
    local z = velocity.Z or 0.0
    local speed_sq = (x * x) + (y * y) + (z * z)
    return speed_sq >= (MIN_GLIDER_SPEED * MIN_GLIDER_SPEED)
end

local function should_continue_for_glider()
    return is_player_gliding()
        and is_player_moving_fast_enough()
        and not is_player_climbing()
        and not is_player_grounded()
end

local function is_grappling_action_active(module)
    if not module or not module.IsValid or not module:IsValid() then
        return false
    end

    if module.IsGrapplingAction then
        local ok, result = pcall(function()
            return module:IsGrapplingAction()
        end)
        return ok and result == true
    end

    return false
end

local function write_command(command)
    local f = io.open(COMMAND_FILE, "w")
    if f then
        f:write(command .. " " .. tostring(os.clock()))
        f:close()
    else
        log("failed to write audio command: " .. command)
    end
end

local function start_audio_server()
    local servers = {}
    for _, path in ipairs(AUDIO_SERVERS) do
        table.insert(servers, string.format("'%s'", path))
    end

    local ps = string.format([[powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$servers=@(%s); foreach($s in $servers){ if(Test-Path -LiteralPath $s){ Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$s; exit 0 } }; exit 2"]],
        table.concat(servers, ",")
    )
    os.execute(ps)
end

local function quit_audio_server()
    write_command("quit")

    local helpers = {}
    for _, path in ipairs(QUIT_HELPERS) do
        table.insert(helpers, string.format("'%s'", path))
    end

    local ps = string.format([[powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$helpers=@(%s); foreach($h in $helpers){ if(Test-Path -LiteralPath $h){ Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$h; exit 0 } }; exit 0"]],
        table.concat(helpers, ",")
    )
    os.execute(ps)
end

local function play_sound(reason)
    local now = os.clock()
    if (now - last_play) < MIN_INTERVAL_SECONDS then
        return
    end

    last_play = now
    audio_active = true
    write_command("play")
    log("sound played: " .. tostring(reason))
end

local function stop_sound(reason)
    if not audio_active then
        return
    end

    audio_active = false
    write_command("stop")
    log("sound stopped: " .. tostring(reason))
end

local function poll_glider_until_end()
    if not audio_active then
        return
    end

    if should_continue_for_glider() then
        ExecuteWithDelay(GLIDER_POLL_MS, poll_glider_until_end)
    else
        stop_sound("glider ended")
    end
end

local function handle_grapple_end(reason)
    ExecuteWithDelay(GRAPPLE_END_GLIDER_GRACE_MS, function()
        if should_continue_for_glider() then
            log("grapple ended; glider keeps audio alive")
            ExecuteWithDelay(GLIDER_POLL_MS, poll_glider_until_end)
        else
            stop_sound(reason)
        end
    end)
end

local function start_grapple_state_monitor(module)
    active_grapple_module = module
    active_monitor_id = active_monitor_id + 1

    local monitor_id = active_monitor_id
    local poll_count = 0
    local saw_active = false

    local function poll()
        if monitor_id ~= active_monitor_id or not audio_active then
            return
        end

        poll_count = poll_count + 1
        local active = is_grappling_action_active(active_grapple_module)

        if active then
            saw_active = true
        elseif saw_active then
            handle_grapple_end("grapple state ended")
            return
        end

        if poll_count < GRAPPLE_STATE_POLL_LIMIT then
            ExecuteWithDelay(GRAPPLE_STATE_POLL_MS, poll)
        end
    end

    ExecuteWithDelay(GRAPPLE_STATE_POLL_MS, poll)
end

local function run_hook_action(hook, context)
    if hook.action == "shot" then
        shot_id = shot_id + 1
        local this_shot = shot_id
        play_sound(hook.path)
        ExecuteWithDelay(MISS_TIMEOUT_MS, function()
            if confirmed_shot_id < this_shot then
                stop_sound("miss timeout after ShotCable")
            end
        end)
    elseif hook.action == "confirm" then
        confirmed_shot_id = shot_id
        start_grapple_state_monitor(context)
        log("grapple confirmed: " .. hook.path)
    elseif hook.action == "grapple_end" then
        handle_grapple_end(hook.path)
    elseif hook.action == "stop" then
        stop_sound(hook.path)
    end
end

local function register_hooks()
    for _, hook in ipairs(HOOKS) do
        local ok, err = pcall(function()
            RegisterHook(hook.path, function(context, ...)
                run_hook_action(hook, context)
            end)
        end)

        if ok then
            log("hook registered: " .. hook.path)
        else
            log("hook failed: " .. hook.path .. " :: " .. tostring(err))
        end
    end
end

log("loading")
start_audio_server()
register_hooks()

RegisterKeyBind(Key.F9, function()
    play_sound("manual F9 test")
end)

RegisterKeyBind(Key.F10, function()
    stop_sound("manual F10 test")
end)

RegisterKeyBind(Key.F11, function()
    quit_audio_server()
    log("audio server quit requested")
end)

log("loaded. F9 tests audio. F10 stops audio. F11 quits audio server.")
