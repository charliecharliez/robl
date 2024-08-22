--!native
--!strict
local SharedTableRegistry = game:GetService("SharedTableRegistry")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Timer = require(ReplicatedStorage:WaitForChild("Both"):WaitForChild("Timer"))

local shared_registry: SharedTable

local IS_OTHER_VM = script:GetAttribute("AlreadyRequired") == true
if IS_OTHER_VM then
	shared_registry = SharedTableRegistry:GetSharedTable("Kinematics")
else
	shared_registry = SharedTable.new()
	shared_registry.instances = {}
	SharedTableRegistry:SetSharedTable("Kinematics", shared_registry)
	script:SetAttribute("AlreadyRequired", true)
end

local IS_SERVER = RunService:IsServer()

local Kinematic = {}

export type KinematicInfo = {
	CFrame: CFrame,
	LinearVelocity: Vector3,
	LinearAcceleration: Vector3,
	AngularVelocity: Vector3,
	AtTime: number,
	Id: number,
}

local interim_registry: {[number]: KinematicInfo} = {}
local gained = 0

local last_id = (IS_SERVER and 0):: number

function Kinematic.new(properties: {
	Id: number?,
	CFrame: CFrame,
	LinearVelocity: Vector3?,
	LinearAcceleration: Vector3?,
	AngularVelocity: Vector3?,
	AtTime: number?
	}): KinematicInfo

	assert(not IS_OTHER_VM, "Cannot instantiate new KinematicInfo in a separate VM")

	if IS_SERVER then
		last_id += 1
	end

	local self = {
		CFrame = properties.CFrame,
		LinearVelocity = properties.LinearVelocity or Vector3.zero,
		LinearAcceleration = properties.LinearAcceleration or Vector3.zero,
		AngularVelocity = properties.AngularVelocity or Vector3.zero,
		AtTime = properties.AtTime or Timer.GetTime(),
		Id = properties.Id or last_id
	}

	interim_registry[self.Id] = self
	gained += 1

	return self
end

function Kinematic.GetCFrameApprox(kinfo: KinematicInfo, eval_time: number?): CFrame
	local dt = (eval_time or Timer.GetTime()) - kinfo.AtTime

	local dpos = kinfo.LinearAcceleration/2 * dt*dt + kinfo.LinearAcceleration * dt

	local current_rot = Vector3.new(kinfo.CFrame:ToEulerAnglesYXZ())
	local drot = kinfo.AngularVelocity * dt
	local new_rot = current_rot + drot
	local rot_cf = CFrame.fromEulerAnglesYXZ(new_rot.X, new_rot.Y, new_rot.Z)

	return CFrame.new(kinfo.CFrame.Position + dpos) * rot_cf
end

function Kinematic.Get(id: number): KinematicInfo
	return IS_OTHER_VM and shared_registry.instances[id] or interim_registry[id]
end

function Kinematic.Update(kinfo: KinematicInfo, properties: {
	CFrame: CFrame?,
	LinearVelocity: Vector3?,
	LinearAcceleration: Vector3?,
	AngularVelocity: Vector3?
	}): ()
	
	if IS_OTHER_VM then
		local new_info = {}
		for k, v in kinfo do
			new_info[k] = properties[k] or kinfo[k]
		end
		shared_registry.instances[new_info.Id] = new_info
	else
		for k, v in kinfo do
			local new_value = properties[k]
			if not new_value then continue end

			kinfo[k] = new_value
		end
		interim_registry[kinfo.Id] = kinfo
	end
end

function Kinematic.Cycle(): ()
	assert(not IS_OTHER_VM, "Cannot force shared update cycle in separate VM")

	if gained == 0 then return end
	shared_registry.instances = interim_registry
	gained = 0
end

function Kinematic.Remove(id: number): ()
	assert(not IS_OTHER_VM, "Cannot remove KinematicInfo in separate VM")

	interim_registry[id] = nil
	gained += 1
end

if IS_OTHER_VM then
	RunService.PreSimulation:Connect(Kinematic.Cycle)
end

return table.freeze(Kinematic)
