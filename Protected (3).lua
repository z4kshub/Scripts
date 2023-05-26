
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local LuaName = "Keysystem v.1.0"

--* Configuration *--
local initialized = false
local sessionid = ""


StarterGui:SetCore("SendNotification", {
    Title = LuaName,
    Text = " Intializing...",
    Duration = 5
})


--* Application Details *--
Name = "ZYrc hub" --* Application Name
Ownerid = "0cQCyCpRhL" --* OwnerID
APPVersion = "1.0"     --* Application Version

local req = game:HttpGet('https://keyauth.win/api/1.1/?name=' .. Name .. '&ownerid=' .. Ownerid .. '&type=init&ver=' .. APPVersion)

if req == "KeyAuth_Invalid" then 
   print(" Error: Application not found.")

   StarterGui:SetCore("SendNotification", {
       Title = LuaName,
       Text = " Error: Application not found.",
       Duration = 3
   })

   return false
end

local data = HttpService:JSONDecode(req)

if data.success == true then
   initialized = true
   sessionid = data.sessionid
   --print(req)
elseif (data.message == "invalidver") then
   print(" Error: Wrong application version..")

   StarterGui:SetCore("SendNotification", {
       Title = LuaName,
       Text = " Error: Wrong application version..",
       Duration = 3
   })

   return false
else
   print(" Error: " .. data.message)
   return false
end

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/PDCloud/Pivl-CDN/main/keyauth/robloxUI.lua"))()
local Window = Library.CreateLib("Keys")

-- Tabs --

local LoginTab = Window:NewTab("Login")
local MainSection = LoginTab:NewSection("Login")

-- Configuration !! KEEP CLEAR !!--
local Password = ""

-- Text Boxes and Login Button --

MainSection:NewTextBox("Serial Key", "Please provide Key.", function(state)
    if state then
        Password = state
    end
end)


MainSection:NewButton("Go to script", "Please provide Key.", function(state)
    if Password == "" then
        StarterGui:SetCore("SendNotification", {
            Title = LuaName,
            Text = "You need to press enter when ur done entering key / Put the correct key",
            Duration = 3
        })
        return false
    end

    Library.Destroy()

    local req = game:HttpGet('https://keyauth.win/api/1.1/?name=' .. Name .. '&ownerid=' .. Ownerid .. '&type=license&key=' .. Password .. '&ver=' .. APPVersion .. '&sessionid=' .. sessionid)
    local data = HttpService:JSONDecode(req)


     if data.success == false then 
        print(" Error: " .. data.message )

       StarterGui:SetCore("SendNotification", {
           Title = LuaName,
           Text = " Error: " .. data.message,
           Duration = 5
       })

        return false
    end

    StarterGui:SetCore("SendNotification", {
        Title = LuaName,
        Text = " Successfully Authorized enjoy :)",
        Duration = 5
    })

    loadstring(game:HttpGet("https://raw.githubusercontent.com/RandomRandom123-jacks/Scripts/main/Protected%20(1).lua"))()
end)
