--!strict
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local StarterPlayer = game:GetService("StarterPlayer")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local WtCam = {}

local camTestPart = workspace:FindFirstChild("CamTest") or Instance.new("Part")
camTestPart.Anchored = true
camTestPart.Transparency = 0
camTestPart.CanCollide = false
camTestPart.CanTouch = false
camTestPart.CanQuery = false
camTestPart.Name = "WtCam_TestPart"
camTestPart.Parent = workspace

local cursorGui = script:WaitForChild("CursorGui"); cursorGui.Enabled = true
cursorGui.Parent = player.PlayerGui
local cursorImage = cursorGui:WaitForChild("ImageLabel"); cursorImage.Visible = false

local cameraAngleX = 0
local cameraAngleY = 0

local function Lerp(x: number, y: number, alpha: number)
	return (1 - alpha) * x + y * alpha
end

local function SanitizeAngle(deg: number): number
	return (deg + 180) % 360 - 180
end

local function CframeToCamAnglesYX(cf: CFrame)
	local rx, ry = cf:ToEulerAnglesYXZ()
	return math.deg(rx), math.deg(ry)
end


local MOUSE_SENS = 1
local ROTATION_RESPONSIVENESS = .95

local isFreeLooking = false

local resetToAngles = {
	X = cameraAngleX,
	Y = cameraAngleY
}

WtCam.Controls = {
	Freelook = Enum.KeyCode.C,
	Zoom = Enum.UserInputType.MouseButton2,
	UnlockMouse = Enum.KeyCode.RightAlt
}

local DEFAULT_SETTINGS do
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = false

	DEFAULT_SETTINGS = {
		OrbitDist = 30,
		VerticalOffset = 5,
		VerticalAngularOffset = 7, --degrees
		Subject = camTestPart,
		StickToSubject = false,
		RaycastParams = params,

		MouseSensitivity = MOUSE_SENS,
		Responsiveness = ROTATION_RESPONSIVENESS,
		FreelookResponsiveness = ROTATION_RESPONSIVENESS * 2
	}

	DEFAULT_SETTINGS.__index = DEFAULT_SETTINGS
end

export type Settings = typeof(setmetatable({}, DEFAULT_SETTINGS))

function WtCam.newSettings(incomplete: {}?): Settings
	return setmetatable(incomplete or {}, DEFAULT_SETTINGS)
end

local currentSettings = WtCam.newSettings()

local function OnFreeLook(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		isFreeLooking = true
		resetToAngles.X = cameraAngleX
		resetToAngles.Y = cameraAngleY
	elseif state == Enum.UserInputState.End then
		isFreeLooking = false
		if not cursorImage.Visible or currentSettings.StickToSubject then
				--[[local rx, ry = currentSettings.Subject:GetPivot():ToEulerAnglesYXZ()
				cameraAngleX = math.deg(ry)
				cameraAngleY = math.deg(rx)]]
			cameraAngleY, cameraAngleX = CframeToCamAnglesYX(currentSettings.Subject:GetPivot())
			return
		end
		cameraAngleX = resetToAngles.X
		cameraAngleY = resetToAngles.Y
	end
end

local isZoomed = false
local function OnAimZoom(_, state: Enum.UserInputState)
	-----------------[[Toggle Zoom]]------------
	if state ~= Enum.UserInputState.Begin then return end
	isZoomed = not isZoomed

	----------------[[Hold Zoom]]------------------
		--[[if state == Enum.UserInputState.Begin then
			isZoomed = true
		elseif state == Enum.UserInputState.End then
			isZoomed = false
		end]]
end

local unlockedMouse = false
local function OnMouseUnlock(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then
		unlockedMouse = true
	elseif state == Enum.UserInputState.End then
		unlockedMouse = false
	end
end

local lastCursorDirection = camera.CFrame.LookVector --placeholder value
local updateBindable = Instance.new("BindableEvent")

local function Update(dt: number)
	UserInputService.MouseBehavior = Enum.MouseBehavior[(unlockedMouse and "Default") or "LockCenter"]
	UserInputService.MouseIconEnabled = unlockedMouse

	local screen_size = camera.ViewportSize
	local aspect_ratio = screen_size.X / screen_size.Y

	local mouseDelta = UserInputService:GetMouseDelta()

	local delta_angle_x = mouseDelta.X / screen_size.X * (camera.FieldOfView * aspect_ratio)
	local delta_angle_y = mouseDelta.Y / screen_size.Y * camera.FieldOfView

	cameraAngleX = SanitizeAngle(cameraAngleX - delta_angle_x * (currentSettings.MouseSensitivity))
	cameraAngleY = SanitizeAngle(cameraAngleY - delta_angle_y * (currentSettings.MouseSensitivity))

	local targetRotation = CFrame.fromEulerAnglesYXZ(math.rad(cameraAngleY), math.rad(cameraAngleX), 0)

	local lerp_factor = isFreeLooking and (currentSettings.FreelookResponsiveness) or (currentSettings.Responsiveness)
	lerp_factor = math.clamp(1 - lerp_factor, 0, 1)

	local steppedRotation = camera.CFrame.Rotation:Lerp(
		targetRotation * CFrame.Angles(-math.rad(currentSettings.VerticalAngularOffset), 0, 0),
		1 - math.pow(lerp_factor, dt) --dont ask why, it just works (constant speed regardless of framerate)
	)

	local subjectCF = currentSettings.Subject:GetPivot()

	local targetFOV = isZoomed and 30 or 70
	camera.FieldOfView = Lerp(camera.FieldOfView, targetFOV, .2)

	local orbitOffset = -steppedRotation.LookVector * currentSettings.OrbitDist
	local originCF = CFrame.new(subjectCF.Position) * steppedRotation * CFrame.new(0, currentSettings.VerticalOffset, 0)

	local cast = workspace:Raycast(originCF.Position, (orbitOffset + .5 * orbitOffset.Unit), currentSettings.RaycastParams)

	camera.CFrame = cast and CFrame.new(cast.Position - orbitOffset.Unit * .5) * steppedRotation or originCF + orbitOffset

	local cursorDirection do
		if currentSettings.StickToSubject then
			cursorDirection = subjectCF.LookVector
		elseif isFreeLooking then
			cursorDirection = lastCursorDirection
		else 
			cursorDirection = targetRotation.LookVector
		end
	end
	lastCursorDirection = cursorDirection

	local imaginaryWorldSpaceCursorPosition = camera.CFrame.Position + cursorDirection * 1000

	local cursorScreenPos: Vector3, visible: boolean = camera:WorldToViewportPoint(imaginaryWorldSpaceCursorPosition)
	cursorImage.Visible = visible
	cursorImage.Position = UDim2.fromOffset(cursorScreenPos.X, cursorScreenPos.Y)

	updateBindable:Fire(cursorDirection, dt)
end

function WtCam.OnUpdate(callback: (newDirection: Vector3, dt: number) -> (...any))
	return updateBindable.Event:Connect(callback)
end

local isBinded = false

local function MakeCharacterVisible()
	local char = player.Character
	if not char then return end
	for _, v in ipairs(char:GetChildren()) do
		if v:IsA("BasePart") then
			v.Transparency = 0
		end
	end
end

local renderConnection: RBXScriptConnection?

function WtCam.Bind(settings_table: Settings?)
	if isBinded then return end

	assert(settings_table == nil or type(settings_table) == "table" and getmetatable(settings_table) == DEFAULT_SETTINGS, "Invalid type for settings argument")

	isBinded = true

	camera.CameraSubject = workspace:FindFirstChildWhichIsA("BasePart", true) --sets subject to random part, hopefully not belonging to a character
	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseIconEnabled = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	currentSettings = settings_table or WtCam.newSettings()
		--[[local rx, ry = currentSettings.Subject:GetPivot():ToEulerAnglesYXZ()
		cameraAngleX = math.deg(ry)
		cameraAngleY = math.deg(rx)]]
	--x axis rotation corresponds with pitch angle, and y axis rotation is yaw angle
	cameraAngleY, cameraAngleX = CframeToCamAnglesYX(currentSettings.Subject:GetPivot())
	--whereas the X and Y here are horizontal and vertical

	currentSettings.RaycastParams:AddToFilter({
		player.Character,
		--workspace:FindFirstChild("ActiveVehicles"),
		--workspace:FindFirstChild("Debris"),
		currentSettings.Subject
	})

	renderConnection = RunService.PreRender:Connect(Update)

	cursorImage.Visible = true

	ContextActionService:BindAction("WtCamFreeLook", OnFreeLook, false, WtCam.Controls.Freelook)
	ContextActionService:BindAction("AimZoom", OnAimZoom, false, WtCam.Controls.Zoom)
	ContextActionService:BindAction("UnlockMouse", OnMouseUnlock, false, WtCam.Controls.UnlockMouse)

	print("Binded War Thunder Camera")
end

function WtCam.Unbind()
	if not isBinded then return end
	isBinded = false

	--RunService:UnbindFromRenderStep("WarThunderCam")
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	camera.CameraType = Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
		camera.Focus = player.Character:GetPivot()
	end
	UserInputService.MouseIconEnabled = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default

	isZoomed = false
	camera.FieldOfView = 70

	cursorImage.Visible = false

	OnAimZoom(nil, Enum.UserInputState.End)
	OnFreeLook(nil, Enum.UserInputState.End)

	ContextActionService:UnbindAction("WtCamFreeLook")
	ContextActionService:UnbindAction("AimZoom")
	ContextActionService:UnbindAction("UnlockMouse")

	print("Unbinded War Thunder Camera")
end

function WtCam.StickToSubject(toggle: boolean)
	currentSettings.StickToSubject = toggle
		--[[if not toggle then
			cameraAngleY, cameraAngleX = CframeToCamAnglesYX(currentSettings.Subject:GetPivot())
		end]]
end

function WtCam.IsStickingToSubject(): boolean
	return currentSettings.StickToSubject
end

function WtCam.IsBinded(): boolean
	return isBinded
end

function WtCam.GetCursorDirection(): Vector3
	return lastCursorDirection
end

function WtCam.GetComponents(): number & number
	return cameraAngleX, cameraAngleY
end

function WtCam.IsVisible(): boolean
	return cursorImage.Visible
end

function WtCam.IsFreelooking(): boolean
	return isFreeLooking
end

function WtCam.GetSettings()
	return currentSettings
end

print("WtCam loaded")

return WtCam
