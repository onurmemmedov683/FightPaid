local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local workspace = game:GetService("Workspace")

local Config = {
    -- Combat Core
    Enabled = true,
    Distance = 15,       
    Cooldown = 0.15,      -- GAME COOLDOWN SYNC
    MyAttackWindow = 0.4, 
    BlockKey = "F",
    MenuKey = "Insert",
    
    -- Automation & Exploits
    AutoAttack = false,
    AutoAttackKicks = true,  
    FastAttack = false,        
    PerfectCounter = true,     
    TargetStrafe = false,      
    StrafeSpeed = 15,          
    StrafeRadius = 5.5,        
    AntiKnockback = true,     
    AntiRagdoll = true,       
    DefaultSpeed = 16,
    
    -- Noclip System Settings
    Noclip = false,
    NoclipKey = "N",
    
    -- Wall Climb Settings
    WallClimb = false,
    ClimbForce = 20,
    
    -- Smart Logic Settings
    SmartHPMode = true,        
    HPThreshold = 35,

    -- Body Aim Configuration
    BodyAim = false,
    BodyAimRadius = 15,

    -- Arm Spinner Configurations
    SpinArms = false,
    SpinSpeed = 20,
    SpinRadius = 3
}

local ATTACK_ANIMATION_IDS = {
    ["122008594977996"] = true, ["108390712390287"] = true, ["92024825578627"]  = true,
    ["138434473879558"] = true, ["119160927304691"] = true, ["119650753709805"] = true
}

local lastBlockTime = 0
local lastMyAttackTime = 0
local currentStrafeAngle = 0
local lastM1PacketTime = 0
local lastKeyPacketTimes = {}
local noclipConnection = nil 
local spinAngle = 0 

local strafeVelocity = Instance.new("LinearVelocity")
local strafeAttachment = Instance.new("Attachment")
strafeVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
strafeVelocity.MaxForce = math.huge

-- Helper to get the closest player in studs
local function getClosestPlayer(maxDist)
    local myChar = LocalPlayer.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return nil end
    local myPos = myChar.HumanoidRootPart.Position
    local closest = nil
    local closestDist = maxDist or math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Humanoid") then
            if player.Character.Humanoid.Health > 0 then
                local dist = (myPos - player.Character.HumanoidRootPart.Position).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closest = player
                end
            end
        end
    end
    return closest
end

-- Smooth Facing & Auto-Aiming Mechanism
local function faceTarget(targetChar)
    local myChar = LocalPlayer.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local targetHrp = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
    if myHrp and targetHrp then
        local targetPos = Vector3.new(targetHrp.Position.X, myHrp.Position.Y, targetHrp.Position.Z)
        myHrp.CFrame = CFrame.lookAt(myHrp.Position, targetPos)
    end
end

-- Fire direct game client packet block
local function fireKeyPacket(keyChar, isPress)
    local now = os.clock()
    local key = tostring(keyChar):lower() .. "_" .. (isPress and "press" or "release")
    local lastSent = lastKeyPacketTimes[key] or 0
    if now - lastSent < 0.1 then return end 
    lastKeyPacketTimes[key] = now

    local packet = game:GetService("ReplicatedStorage"):FindFirstChild("Packet")
    if packet then
        local remote = packet:FindFirstChild("RemoteEvent")
        if remote then
            pcall(function()
                local action = isPress and "keypress" or "keyrelease"
                local rawStr = string.char(5, #action) .. action .. string.char(11, 1) .. tostring(keyChar):lower() .. string.char(0, 0, 0, 0)
                if typeof(buffer) == "table" and buffer.fromstring then
                    remote:FireServer(buffer.fromstring(rawStr))
                else
                    remote:FireServer(rawStr)
                end
            end)
        end
    end
end

local function fireM1Packet()
    local now = os.clock()
    if now - lastM1PacketTime < 0.05 then return end 
    lastM1PacketTime = now

    local packet = game:GetService("ReplicatedStorage"):FindFirstChild("Packet")
    if packet then
        local remote = packet:FindFirstChild("RemoteEvent")
        if remote then
            pcall(function()
                local rawStr = string.char(5, 3) .. "lmb" .. string.char(0, 0, 0, 0, 0)
                if typeof(buffer) == "table" and buffer.fromstring then
                    remote:FireServer(buffer.fromstring(rawStr))
                else
                    remote:FireServer(rawStr)
                end
            end)
        end
    end
end

local function getBlockInputType()
    local keyStr = Config.BlockKey
    if keyStr == "MouseButton1" then return "Mouse", Enum.UserInputType.MouseButton1
    elseif keyStr == "MouseButton2" then return "Mouse", Enum.UserInputType.MouseButton2
    else
        local success, keycode = pcall(function() return Enum.KeyCode[keyStr] end)
        if success and keycode then return "Key", keycode else return "Key", Enum.KeyCode.F end
    end
end

-- Precision M1 execution bypassing queue lock
local function performCounterAttack()
    task.defer(function()
        local myChar = LocalPlayer.Character
        local tool = myChar and myChar:FindFirstChildOfClass("Tool")
        if tool then 
            pcall(function() tool:Activate() end) 
        end
        pcall(fireM1Packet)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
        task.wait(0.02)
        VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
    end)
end

-- Track player manual inputs to prevent auto-block combo disruption
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.E then
        lastMyAttackTime = os.clock()
    end
end)

-- Detect if own character is playing an attack animation track
local function isLocalPlayerAttacking()
    local char = LocalPlayer.Character
    local animator = char and char.Humanoid and char.Humanoid:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            local name = track.Name:lower()
            local id = string.match(track.Animation.AnimationId, "%d+")
            if name:find("attack") or name:find("swing") or name:find("punch") or name:find("kick") or ATTACK_ANIMATION_IDS[id] then
                if track.IsPlaying and track.WeightCurrent > 0.1 then
                    return true
                end
            end
        end
    end
    return false
end

-- Continuous hold/active attack detection
RunService.Heartbeat:Connect(function()
    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) or isLocalPlayerAttacking() then
        lastMyAttackTime = os.clock()
    end
end)

-- Mobile Button Caching
local cachedBlockButton = nil
local lastCacheTime = 0

local function findMobileBlockButton()
    local currentTime = os.clock()
    if cachedBlockButton and cachedBlockButton.Parent and (currentTime - lastCacheTime < 10) then
        return cachedBlockButton
    end
    
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil end
    
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Enabled then
            for _, desc in ipairs(gui:GetChildren()) do
                if desc:IsA("ImageButton") or desc:IsA("TextButton") then
                    local name = desc.Name:lower()
                    if name:find("block") or name:find("parry") or name:find("shield") then
                        cachedBlockButton = desc
                        lastCacheTime = currentTime
                        return desc
                    end
                end
                for _, sub in ipairs(desc:GetChildren()) do
                    if sub:IsA("ImageButton") or sub:IsA("TextButton") then
                        local name = sub.Name:lower()
                        if name:find("block") or name:find("parry") or name:find("shield") then
                            cachedBlockButton = sub
                            lastCacheTime = currentTime
                            return sub
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function triggerMobileBlock()
    local boundActions = {"Block", "Parry", "Defend", "Shield", "Guard", "BlockAction", "ParryAction"}
    for _, actionName in ipairs(boundActions) do
        pcall(function()
            ContextActionService:CallFunction(actionName, Enum.UserInputState.Begin, nil)
            task.delay(0.05, function()
                ContextActionService:CallFunction(actionName, Enum.UserInputState.End, nil)
            end)
        end)
    end
    
    pcall(function()
        local button = findMobileBlockButton()
        if button then
            local pos = button.AbsolutePosition + (button.AbsoluteSize / 2)
            VirtualInputManager:SendTouchEvent(10, Enum.UserInputState.Begin, pos)
            task.delay(0.05, function()
                VirtualInputManager:SendTouchEvent(10, Enum.UserInputState.End, pos)
            end)
        end
    end)
end

-- Adaptive block mechanism considering game cooldown limits
local function triggerBlock(isLowHP)
    local currentTime = os.clock()
    
    local currentAttackWindow = isLowHP and Config.MyAttackWindow or (Config.MyAttackWindow * 2.5)
    if currentTime - lastMyAttackTime < currentAttackWindow then return end
    
    if currentTime - lastBlockTime < Config.Cooldown then 
        if Config.PerfectCounter then performCounterAttack() end
        return 
    end
    
    lastBlockTime = currentTime

    task.spawn(function()
        if UserInputService.TouchEnabled then
            pcall(triggerMobileBlock)
        end

        local blockType, blockCode = getBlockInputType()
        if blockType == "Mouse" then
            local isRightClick = (blockCode == Enum.UserInputType.MouseButton2)
            VirtualInputManager:SendMouseButtonEvent(0, 0, isRightClick and 1 or 0, true, game, 1)
            
            if Config.PerfectCounter then performCounterAttack() end
            
            task.wait(0.05) 
            VirtualInputManager:SendMouseButtonEvent(0, 0, isRightClick and 1 or 0, false, game, 1)
        else
            VirtualInputManager:SendKeyEvent(true, blockCode, false, game)
            
            if Config.PerfectCounter then performCounterAttack() end
            
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, blockCode, false, game)
        end
    end)
end

-- Build GUI Panel
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
   Name = "ETWare V6 | Made By EyeG & Tyler Durden",
   LoadingTitle = "Fight Club",
   LoadingSubtitle = "ETWare",
   Theme = "Amethyst",
   DisableBuildWarnings = true,
   ConfigurationSaving = { Enabled = true, FolderName = "Sentinel_PulseCore", FileName = "Sentinel" },
   KeySystem = false
})

local CombatTab = Window:CreateTab("Combat", 0)
local MovementTab = Window:CreateTab("Movement", 0)
local SettingsTab = Window:CreateTab("Settings", 0)

-- COMBAT TAB
CombatTab:CreateSection("Core Automation")
CombatTab:CreateToggle({ Name = "Enable Auto-Block (PC Only)", CurrentValue = Config.Enabled, Flag = "AutoBlockToggle", Callback = function(v) Config.Enabled = v end })
CombatTab:CreateToggle({ Name = "Perfect Counter (M1 Focus)", CurrentValue = Config.PerfectCounter, Flag = "CounterToggle", Callback = function(v) Config.PerfectCounter = v end })
CombatTab:CreateToggle({ Name = "Enable Body Aim", CurrentValue = Config.BodyAim, Flag = "BodyAimToggle", Callback = function(v) Config.BodyAim = v end })
CombatTab:CreateToggle({ Name = "Smart HP-Adaptive Mode", CurrentValue = Config.SmartHPMode, Flag = "SmartHP", Callback = function(v) Config.SmartHPMode = v end })
CombatTab:CreateToggle({ Name = "Enable Killaura", CurrentValue = Config.AutoAttack, Flag = "AutoAttackToggle", Callback = function(v) Config.AutoAttack = v end })
CombatTab:CreateToggle({ Name = "Fast Attack (Overdrive Method)", CurrentValue = Config.FastAttack, Flag = "FastAttackToggle", Callback = function(v) Config.FastAttack = v end })
CombatTab:CreateToggle({ Name = "Arm Spinner (Kolları Döndür)", CurrentValue = Config.SpinArms, Flag = "SpinArmsToggle", Callback = function(v) Config.SpinArms = v end })
CombatTab:CreateInput({ Name = "Spinner Speed (Hız)", PlaceholderText = tostring(Config.SpinSpeed), Callback = function(t) local n = tonumber(t) if n then Config.SpinSpeed = n end end })
CombatTab:CreateInput({ Name = "Spinner Radius (Çap)", PlaceholderText = tostring(Config.SpinRadius), Callback = function(t) local n = tonumber(t) if n then Config.SpinRadius = n end end }) 

CombatTab:CreateSection("Timings Configuration")
CombatTab:CreateInput({ Name = "Check Distance (studs)", PlaceholderText = tostring(Config.Distance), Callback = function(t) local n = tonumber(t) if n then Config.Distance = n end end })
CombatTab:CreateInput({ Name = "Aim Radius (studs)", PlaceholderText = tostring(Config.BodyAimRadius), Callback = function(t) local n = tonumber(t) if n then Config.BodyAimRadius = n end end })
CombatTab:CreateInput({ Name = "Internal Game Cooldown (sec)", PlaceholderText = tostring(Config.Cooldown), Callback = function(t) local n = tonumber(t) if n then Config.Cooldown = n end end })


-- MOVEMENT TAB
MovementTab:CreateSection("Exploit Mechanisms")
MovementTab:CreateToggle({ Name = "Velocity Anti-Knockback", CurrentValue = Config.AntiKnockback, Flag = "AntiKB", Callback = function(v) Config.AntiKnockback = v end })
MovementTab:CreateToggle({ Name = "Anti-Ragdoll / Anti-Stun", CurrentValue = Config.AntiRagdoll, Flag = "AntiRagdoll", Callback = function(v) Config.AntiRagdoll = v end })
MovementTab:CreateToggle({ Name = "Wall Climb (Spider)", CurrentValue = Config.WallClimb, Flag = "WallClimbToggle", Callback = function(v) Config.WallClimb = v end })
MovementTab:CreateInput({ Name = "Set Force WalkSpeed", PlaceholderText = tostring(Config.DefaultSpeed), Callback = function(t) local n = tonumber(t) if n then Config.DefaultSpeed = n end end })

MovementTab:CreateSection("Noclip System")
local NoclipToggle = MovementTab:CreateToggle({ 
    Name = "Noclip (Duvarlardan Geçme)", 
    CurrentValue = Config.Noclip, 
    Flag = "NoclipToggle", 
    Callback = function(state) 
        Config.Noclip = state
        
        if state then
            if not noclipConnection then
                noclipConnection = RunService.Stepped:Connect(function()
                    local character = LocalPlayer.Character
                    if character then
                        for _, part in ipairs(character:GetDescendants()) do
                            if part:IsA("BasePart") and part.CanCollide then
                                part.CanCollide = false
                            end
                        end
                    end
                end)
            end
            Rayfield:Notify({
                Title = "Noclip Sistemi",
                Content = "Noclip Aktif Edildi! (Enabled)",
                Duration = 2,
                Image = 4483362458
            })
        else
            if noclipConnection then
                noclipConnection:Disconnect()
                noclipConnection = nil
            end
            Rayfield:Notify({
                Title = "Noclip Sistemi",
                Content = "Noclip Devre Dışı Bırakıldı! (Disabled)",
                Duration = 2,
                Image = 4483362458
            })
        end
    end 
})

MovementTab:CreateKeybind({
    Name = "Noclip Kısayol Tuşu",
    CurrentKeybind = Config.NoclipKey,
    HoldToInteract = false,
    Flag = "NoclipKeybind",
    Callback = function()
        NoclipToggle:Set(not Config.Noclip)
    end,
})

MovementTab:CreateSection("Combat Navigation")
MovementTab:CreateToggle({ Name = "Target Strafe (Velocity Orbit)", CurrentValue = Config.TargetStrafe, Flag = "TargetStrafe", Callback = function(v) Config.TargetStrafe = v end })
MovementTab:CreateInput({ Name = "Strafe Orbit Speed", PlaceholderText = tostring(Config.StrafeSpeed), Callback = function(t) local n = tonumber(t) if n then Config.StrafeSpeed = n end end })
MovementTab:CreateInput({ Name = "Strafe Radius (Distance)", PlaceholderText = tostring(Config.StrafeRadius), Callback = function(t) local n = tonumber(t) if n then Config.StrafeRadius = n end end })

-- Teleportation
MovementTab:CreateSection("Teleportation")
MovementTab:CreateInput({
    Name = "Player Name",
    PlaceholderText = "Oyuncu ismini gir ve Enter'a bas",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        local playerName = Text
        local found = false
        
        for _, player in pairs(game.Players:GetPlayers()) do
            if player.Name:lower():sub(1, #playerName) == playerName:lower() or player.DisplayName:lower():sub(1, #playerName) == playerName:lower() then
                found = true
                if player.Character and player.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                    LocalPlayer.Character.HumanoidRootPart.CFrame = player.Character.HumanoidRootPart.CFrame
                    
                    Rayfield:Notify({
                        Title = "Işınlanma Başarılı",
                        Content = player.Name .. " adlı oyuncuya ışınlandın.",
                        Duration = 3,
                        Image = 4483362458
                    })
                end
                break
            end
        end

        if not found and playerName ~= "" then
            Rayfield:Notify({
                Title = "Hata",
                Content = "Oyuncu bulunamadı.",
                Duration = 3,
                Image = 4483362458
            })
        end
    end,
})

-- Admin
MovementTab:CreateSection("Admin")
MovementTab:CreateButton({
    Name = "Infinite Yield",
    Callback = function()
        pcall(function()
            loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
        end)
        Rayfield:Notify({
            Title = "Infinite Yield",
            Content = "Admin panel loaded!",
            Duration = 3,
            Image = 4483362458
        })
    end,
})

-- SETTINGS TAB
SettingsTab:CreateSection("Keybinds")
SettingsTab:CreateInput({ Name = "Block Keybind", PlaceholderText = Config.BlockKey, Callback = function(t) Config.BlockKey = t end })

local TelemetryParagraph = CombatTab:CreateParagraph({Title = "TELEMETRY STATUS", Content = "Active"})

Rayfield:Notify({ Title = "Sentinel v7.5", Content = "Ready", Duration = 4, Image = 0 })

-- Persistent Animation Cache variables for Wall Climb
local currentClimbAnim = nil
local lastClimbChar = nil

-- Main Heartbeat Loop
RunService.Heartbeat:Connect(function(dt)
    local character = LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") or not character:FindFirstChild("Humanoid") then 
        strafeVelocity.Enabled = false
        if TelemetryParagraph then
            TelemetryParagraph:Set({Title = "VICINITY TELEMETRY", Content = "OFFLINE: Character not found."})
        end
        return 
    end
    
    local humanoid = character.Humanoid
    local myRoot = character.HumanoidRootPart
    local myPos = myRoot.Position
    
    local myHealthPercent = (humanoid.Health / humanoid.MaxHealth) * 100
    local isLowHP = Config.SmartHPMode and (myHealthPercent <= Config.HPThreshold)

    -- ARM SPINNER (NEW) 
    if Config.SpinArms then
        local torso = character:FindFirstChild("Torso")
        local rightShoulder = torso and torso:FindFirstChild("Right Shoulder")
        local leftShoulder = torso and torso:FindFirstChild("Left Shoulder")
        
        if rightShoulder and leftShoulder then
            spinAngle = spinAngle + Config.SpinSpeed * dt
            
            local rightX = math.cos(spinAngle) * Config.SpinRadius
            local rightZ = math.sin(spinAngle) * Config.SpinRadius
            rightShoulder.C0 = CFrame.new(rightX, 0.5, rightZ) * CFrame.Angles(0, -spinAngle + math.rad(90), math.rad(90))
            
            local leftAngle = spinAngle + math.pi 
            local leftX = math.cos(leftAngle) * Config.SpinRadius
            local leftZ = math.sin(leftAngle) * Config.SpinRadius
            leftShoulder.C0 = CFrame.new(leftX, 0.5, leftZ) * CFrame.Angles(0, -leftAngle + math.rad(90), math.rad(90))
        end
    end

    -- Anti-Ragdoll
    if Config.AntiRagdoll then
        if humanoid.PlatformStand or character:GetAttribute("Stunned") or character:GetAttribute("Ragdoll") then
            humanoid.PlatformStand = false
            pcall(function() character:SetAttribute("Stunned", false) character:SetAttribute("Ragdoll", false) end)
        end
        if humanoid:GetState() == Enum.HumanoidStateType.Physics then humanoid:ChangeState(Enum.HumanoidStateType.Running) end
        humanoid.WalkSpeed = Config.DefaultSpeed
    end

    -- Anti-Knockback
    if Config.AntiKnockback then
        for _, obj in ipairs(myRoot:GetChildren()) do
            if (obj:IsA("BodyVelocity") or obj:IsA("LinearVelocity") or obj:IsA("VectorForce") or obj:IsA("BodyForce")) and obj ~= strafeVelocity then
                obj:Destroy()
            end
        end
        myRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        
        local vel = myRoot.AssemblyLinearVelocity
        if vel.Magnitude > 25 then
            myRoot.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
        end
    end

    -- WALL CLIMB SPIDER
    if Config.WallClimb then
        local leftFoot = character:FindFirstChild("LeftFoot") or character:FindFirstChild("LeftLeg") or myRoot
        if leftFoot then
            -- Safely refresh character animation references when character respawns
            if lastClimbChar ~= character then
                lastClimbChar = character
                currentClimbAnim = nil
                pcall(function()
                    local animateFolder = character:FindFirstChild("Animate")
                    local climbAnimAsset = animateFolder and animateFolder:FindFirstChild("climb") and animateFolder.climb:FindFirstChild("ClimbAnim")
                    if climbAnimAsset then
                        currentClimbAnim = humanoid:LoadAnimation(climbAnimAsset)
                    end
                end)
            end

            local raycastParams = RaycastParams.new()
            raycastParams.FilterDescendantsInstances = {character}
            
            local origin = leftFoot.Position
            local direction = myRoot.CFrame.LookVector * 1.3
            local raycastResult = workspace:Raycast(origin, direction, raycastParams)

            if raycastResult and raycastResult.Instance then
                -- Apply climb velocity seamlessly
                myRoot.AssemblyLinearVelocity = Vector3.new(myRoot.AssemblyLinearVelocity.X, Config.ClimbForce, myRoot.AssemblyLinearVelocity.Z)
                
                if humanoid:GetState() ~= Enum.HumanoidStateType.Climbing then
                    humanoid:ChangeState(Enum.HumanoidStateType.Climbing)
                end

                if currentClimbAnim and not currentClimbAnim.IsPlaying then
                    currentClimbAnim:Play()
                end
            else
                if currentClimbAnim and currentClimbAnim.IsPlaying then
                    currentClimbAnim:Stop()
                end
            end
        end
    else
        if currentClimbAnim and currentClimbAnim.IsPlaying then
            currentClimbAnim:Stop()
        end
    end

    local closestPlayer = nil
    local closestDistance = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("Humanoid") and player.Character:FindFirstChild("HumanoidRootPart") then
            local enemyChar = player.Character
            local distance = (myPos - enemyChar.HumanoidRootPart.Position).Magnitude

            if distance < closestDistance then
                closestDistance = distance
                closestPlayer = player
            end

            -- Auto-Block Engine
            if Config.Enabled and distance <= (isLowHP and (Config.Distance + 2) or Config.Distance) then
                if not isLowHP and math.random(1, 3) == 1 then continue end

                local animator = enemyChar.Humanoid:FindFirstChildOfClass("Animator")
                if animator then
                    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                        local animId = string.match(track.Animation.AnimationId, "%d+")
                        local trackName = track.Name:lower()
                        local isAttackAnim = ATTACK_ANIMATION_IDS[animId] or 
                                             trackName:find("attack") or 
                                             trackName:find("swing") or 
                                             trackName:find("punch") or 
                                             trackName:find("kick") or 
                                             trackName:find("slash") or 
                                             trackName:find("strike")

                        if isAttackAnim and track.IsPlaying and track.WeightCurrent > 0.15 then
                            if track.TimePosition / track.Length >= 0.05 then
                                triggerBlock(isLowHP)
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    -- TARGET AIM LOCK
    if Config.BodyAim and closestPlayer and closestDistance <= Config.BodyAimRadius then
        faceTarget(closestPlayer.Character)
    end

    -- TARGET STRAFE ENGINE
    if Config.TargetStrafe and closestPlayer and closestDistance <= 25 then
        local enemyRoot = closestPlayer.Character:FindFirstChild("HumanoidRootPart")
        if enemyRoot then
            if strafeAttachment.Parent ~= myRoot then
                strafeAttachment.Parent = myRoot
                strafeVelocity.Attachment0 = strafeAttachment
                strafeVelocity.Parent = myRoot
            end
            
            strafeVelocity.Enabled = true
            currentStrafeAngle = currentStrafeAngle + (math.rad(Config.StrafeSpeed) * 0.7)
            
            local targetHeight = enemyRoot.Position.Y - 0.5
            local offset = Vector3.new(math.cos(currentStrafeAngle) * Config.StrafeRadius, 0, math.sin(currentStrafeAngle) * Config.StrafeRadius)
            local desiredPosition = Vector3.new(enemyRoot.Position.X + offset.X, targetHeight, enemyRoot.Position.Z + offset.Z)
            
            local velocityVector = (desiredPosition - myRoot.Position) * 32
            strafeVelocity.VectorVelocity = Vector3.new(velocityVector.X, 0, velocityVector.Z)
            myRoot.CFrame = CFrame.new(myRoot.Position, Vector3.new(enemyRoot.Position.X, myRoot.Position.Y, enemyRoot.Position.Z))
        else
            strafeVelocity.Enabled = false
        end
    else
        strafeVelocity.Enabled = false
    end

    -- Static UI Updates
    if closestPlayer then
        local displayDist = string.format("%.1f", closestDistance)
        if TelemetryParagraph then
            TelemetryParagraph:Set({Title = "TARGET LOCKED", Content = "Tracking Nearest Enemy | Range: " .. displayDist .. " studs"})
        end
    else
        if TelemetryParagraph then
            TelemetryParagraph:Set({Title = "SCANNING", Content = "No Targets in Range"})
        end
    end
end)

-- Overdrive Fast Attack Engine
RunService.PreSimulation:Connect(function()
    if Config.FastAttack then
        pcall(function()
            local char = LocalPlayer.Character
            local animator = char and char.Humanoid and char.Humanoid:FindFirstChildOfClass("Animator")
            if animator then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    local name = track.Name:lower()
                    local id = string.match(track.Animation.AnimationId, "%d+")
                    if name:find("attack") or name:find("swing") or name:find("punch") or name:find("kick") or ATTACK_ANIMATION_IDS[id] then
                        track:AdjustSpeed(12.0)
                    end
                end
            end
        end)
    end
end)

workspace.DescendantAdded:Connect(function(descendant)
    if Config.AntiKnockback and descendant:IsDescendantOf(LocalPlayer.Character or game) then
        if descendant:IsA("VelocityConstraint") or descendant:IsA("NoCollisionConstraint") then
            task.defer(function() descendant:Destroy() end)
        end
    end
end)

-- Killaura Logic
task.spawn(function()
    local lastAttackInputTime = 0
    while task.wait(0.01) do
        if Config.AutoAttack then
            pcall(function()
                local character = LocalPlayer.Character
                if not character or not character:FindFirstChild("HumanoidRootPart") then return end
                local myPos = character.HumanoidRootPart.Position
                
                for _, player in ipairs(Players:GetPlayers()) do
                    if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Humanoid") then
                        if player.Character.Humanoid.Health > 0 then
                            local dist = (myPos - player.Character.HumanoidRootPart.Position).Magnitude
                            if dist < 7 then
                                local currentTime = os.clock()
                                if currentTime - lastAttackInputTime >= 0.05 then
                                    lastAttackInputTime = currentTime
                                    if Config.BodyAim then
                                        faceTarget(player.Character)
                                    end
                                    performCounterAttack()
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
end)
