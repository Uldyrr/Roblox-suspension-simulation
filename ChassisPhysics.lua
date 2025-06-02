-- Services
local uisService = game:GetService("UserInputService")
local rn = game:GetService("RunService")


-- Constants
local SIMULATION_TARGETSTEPS: number = 240   			        -- Hz
local SIMULATION_DT: number = 1 / SIMULATION_TARGETSTEPS  -- s
local SIMULATION_RAYCASTLENGTH: number = -100
local SIMULATION_RAYCASTMAXDISTANCE: number = 100

local DEBUG: boolean = false
local DEBUG_STEPKEY: Enum.KeyCode = Enum.KeyCode.Return
local DEBUG_LOGDECIMALS: number = 2
local DEBUG_HIGHLIGHT_FILLTRANSPARENCY: number = 0.5
local DEBUG_COLOR_OBJECT: Color3 = Color3.fromRGB(0, 255, 0)
local DEBUG_COLOR_FORCE: Color3 = Color3.fromRGB(255, 0, 0)
local DEBUG_COLOR_VELOCITY: Color3 = Color3.fromRGB(0, 255, 255)
local DEBUG_COLOR_CONTACT: Color3 = Color3.fromRGB(255, 0, 255)

local CHASSISPHYSICS_RAYCASTPARAMS: RaycastParams = RaycastParams.new()
CHASSISPHYSICS_RAYCASTPARAMS.FilterType = Enum.RaycastFilterType.Exclude
CHASSISPHYSICS_RAYCASTPARAMS.IgnoreWater = true
CHASSISPHYSICS_RAYCASTPARAMS.RespectCanCollide = true

local MATH_DEG2RAD: number = math.rad(1)
local MATH_STUDS2METERS: number = 0.28



-- static class SimulationDebug
type SimulationDebug = {
	DebugFolder: Folder,
	DebugChassisOrigin: Part,
	DebugForces: {Part},
	
	ChassisStartCFrame: CFrame,
	
	DebugSimulationIteration: number,
	DebugStepKeyPressed: boolean,
	
	ToString: (number, number) -> string,

	Init: () -> (),
	DebugStart: (Model, {[Attachment]: Vector3}) -> (),
	DebugVector: (Vector3, Vector3, Color3?, string?, number?) -> (),
	DebugContact: (Vector3, Color3?, string?) -> (),
	DebugStep: (Model, CFrame, Vector3) -> (),
	DebugEnd: (Model) -> ()
}


local SimulationDebug: SimulationDebug = {}


-- static helper functions
function SimulationDebug:ToString(value: number, decimals: number): string
	return tostring(math.floor(value * 10^decimals) / 10^decimals)
end


-- static functions
function SimulationDebug:Init(): nil
	if DEBUG == false then return end
	
	self.DebugFolder = Instance.new("Folder", workspace)
	self.DebugFolder.Name = "SimulationDebug"
	
	self.DebugChassisPrediction = Instance.new("Part", self.DebugFolder)
	self.DebugChassisPrediction.Name = "SimulationChassisPrediction"
	self.DebugChassisPrediction.Anchored = true
	self.DebugChassisPrediction.CanCollide = false
	self.DebugChassisPrediction.CanQuery = false
	self.DebugChassisPrediction.Size = Vector3.new(9, 1.182, 20)
	self.DebugChassisPrediction.Transparency = 1
	
	local predictionHighlight: Highlight = Instance.new("Highlight", self.DebugChassisPrediction)
	predictionHighlight.FillColor = DEBUG_COLOR_OBJECT
	predictionHighlight.FillTransparency = DEBUG_HIGHLIGHT_FILLTRANSPARENCY
	predictionHighlight.OutlineTransparency = 1
	
	self.DebugSimulationIteration = 0
end


function SimulationDebug:DebugStart(chassis: Model): nil
	self.DebugChassisPrediction.Transparency = 0
	
	self.ChassisStartCFrame = chassis.Engine.CFrame
	
	self.DebugSimulationIteration += 1
	
	warn(`--- Simulation #{self.DebugSimulationIteration} ---`)
end


function SimulationDebug:DebugVector(origin: Vector3, direction: Vector3, color: Color3?, label: string?, scale: number?): nil
	local debugVector: Part = Instance.new("Part", self.DebugFolder)
	debugVector:SetAttribute("DebugPart", true)
	debugVector.Name = label or "DebugVector"
	debugVector.Size = Vector3.new(0.1, 0.1, direction.Magnitude / (scale or 1))
	debugVector.CFrame = CFrame.new(origin, origin + direction) * CFrame.new(0, 0, -debugVector.Size.Z * 0.5)
	debugVector.Anchored = true
	debugVector.CanCollide = false
	debugVector.CanQuery = false
	
	local debugVectorHighlight: Highlight = Instance.new("Highlight", debugVector)
	debugVectorHighlight.FillColor = color or Color3.fromRGB(255, 255, 255)
	debugVectorHighlight.FillTransparency = DEBUG_HIGHLIGHT_FILLTRANSPARENCY
	debugVectorHighlight.OutlineTransparency = 1
	
	warn(`{label.. " | " or ""} [{self:ToString(direction.X, DEBUG_LOGDECIMALS)}, {self:ToString(direction.Y, DEBUG_LOGDECIMALS)}, {self:ToString(direction.Z, DEBUG_LOGDECIMALS)}]`)
end


function SimulationDebug:DebugContact(origin: Vector3, color: Color3?, label: string?): nil
	local debugContact: Part = Instance.new("Part", self.DebugFolder)
	debugContact:SetAttribute("DebugPart", true)
	debugContact.Name = label or "DebugContact"
	debugContact.Shape = Enum.PartType.Ball
	debugContact.Size = Vector3.new(0.5, 0.5, 0.5)
	debugContact.Position = origin
	debugContact.Anchored = true
	debugContact.CanCollide = false
	debugContact.CanQuery = false

	local debugVectorHighlight: Highlight = Instance.new("Highlight", debugContact)
	debugVectorHighlight.FillColor = color or Color3.fromRGB(255, 255, 255)
	debugVectorHighlight.FillTransparency = DEBUG_HIGHLIGHT_FILLTRANSPARENCY
	debugVectorHighlight.OutlineTransparency = 1

	warn(`{label.. " | " or ""} [{self:ToString(origin.X, DEBUG_LOGDECIMALS)}, {self:ToString(origin.Y, DEBUG_LOGDECIMALS)}, {self:ToString(origin.Z, DEBUG_LOGDECIMALS)}]`)
end


function SimulationDebug:DebugStep(chassis: Model, chassisCFramePrediction: CFrame, chassisPredictedVelocity: Vector3): nil
	self.DebugChassisPrediction.CFrame = chassisCFramePrediction

	self:DebugVector(chassisCFramePrediction.Position, chassisPredictedVelocity, DEBUG_COLOR_VELOCITY, "Predicted velocity")

	chassis.Engine.Anchored = true
	
	local stepKeyPressedToggle: boolean = uisService:IsKeyDown(DEBUG_STEPKEY)
	
	while true do 
		task.wait()
		
		local stepKeyPressed: boolean = uisService:IsKeyDown(DEBUG_STEPKEY)
		
		self.DebugStepKeyPressed = self.DebugStepKeyPressed == false and stepKeyPressed and stepKeyPressed ~= stepKeyPressedToggle
		stepKeyPressedToggle = stepKeyPressed
		
		if self.DebugStepKeyPressed then break end
	end
	
	-- Debug: Cleanup
	for _, debugPart: part in self.DebugFolder:GetChildren() do
		if debugPart:GetAttribute("DebugPart") ~= true then continue end
		
		debugPart:Destroy()
	end
	
	chassis.Engine.Anchored = false
end


function SimulationDebug:DebugEnd(chassis: Model): nil
	chassis.Engine.CFrame = self.ChassisStartCFrame
	
	self.DebugChassisPrediction.Transparency = 1
	
	rn.PreSimulation:Wait()
end


-- static class ChassisPhysics
local ChassisPhysics = {}


-- Public constants
ChassisPhysics.DEBUG = DEBUG


-- Raycast hit distance helper function
function ChassisPhysics:DistanceRaycast(origin: Vector3, direction: Vector3): number
	local result: RaycastResult = workspace:Raycast(origin, direction, CHASSISPHYSICS_RAYCASTPARAMS)
	
	return result and result.Distance or SIMULATION_RAYCASTMAXDISTANCE
end


-- Raycast hit position helper function
function ChassisPhysics:PositionRaycast(origin: Vector3, direction: Vector3): Vector3
	local result: RaycastResult = workspace:Raycast(origin, direction, CHASSISPHYSICS_RAYCASTPARAMS)

	return result and result.Position or origin + direction
end


-- Simulates, estimates, and calculates inbetween frames the car's next traction and suspension values
function ChassisPhysics:SubstepSimulation(chassis: Model, control: {Hold: number, Brake: number, BrakeAmt: number, Forward: number}, settings: {Height: number, SuspensionDampeningRatio: number, SuspensionRange: number}, frameTime: number): nil
	local engine: BasePart = chassis.Engine :: BasePart
	local wheelsAtts: {Attachment} = engine:GetChildren() 
	local suspensionStartCenterDist: {[Attachment]: number} = {}
	
	for _, wheelAtt: Attachment in wheelsAtts do
		suspensionStartCenterDist[wheelAtt] = settings.SuspensionRange + wheelAtt.Position.Y
	end
	
	-- Simulation: Initialize
	local simulationSteps: number = math.clamp(math.floor(frameTime / SIMULATION_DT), 1, SIMULATION_TARGETSTEPS)
	local simulationChassisMass: Vector3 = engine.AssemblyMass
	local simulationChassisCFrame: CFrame = engine.CFrame
	local simulationChassisPosition: Vector3 = engine.Position
	local simulationChassisRotation: Vector3 = engine.Rotation
	local simulationChassisVelocity: Vector3 = engine.AssemblyLinearVelocity
	local simulationChassisAngularVelocity: Vector3 = engine.AssemblyAngularVelocity
	
	local springSprungMassForce: number = simulationChassisMass * workspace.Gravity / #wheelsAtts
	local springStiffness: number = springSprungMassForce / settings.SuspensionRange
	local springDamper: number = settings.SuspensionDampeningRatio * 2 * math.sqrt(springStiffness * simulationChassisMass)
	
	CHASSISPHYSICS_RAYCASTPARAMS.FilterDescendantsInstances = {chassis}
	
	if DEBUG then SimulationDebug:DebugStart(chassis) end
	
	-- Simulation: Simulate and estimate 
	for i = 1, simulationSteps do
		if DEBUG then warn("----------------------------------------") end
		
		-- Simulation: Gravity
		simulationChassisVelocity -= Vector3.yAxis * workspace.Gravity * SIMULATION_DT

		-- Simulation: Simulate springs
		for _, wheelAtt: Attachment in wheelsAtts do
			local springSurfaceContactDist: number = ChassisPhysics:DistanceRaycast(wheelAtt.WorldPosition, simulationChassisCFrame.UpVector * SIMULATION_RAYCASTLENGTH)
			local springCompressionDist: number = settings.SuspensionRange + math.clamp(wheelAtt.Wheel.Size.Y * 0.5 - springSurfaceContactDist, -settings.SuspensionRange, settings.SuspensionRange)
			local springContactSpeed: number = MATH_STUDS2METERS * (math.lerp(suspensionStartCenterDist[wheelAtt], springCompressionDist, i / simulationSteps) - settings.SuspensionRange - wheelAtt.Position.Y) / SIMULATION_DT
			local springForce: Vector3 = simulationChassisCFrame.UpVector * (springStiffness * springCompressionDist + springContactSpeed * springDamper)
			
			engine:ApplyImpulseAtPosition(springForce * SIMULATION_DT, wheelAtt.WorldPosition)
			
			wheelAtt.Position = Vector3.new(wheelAtt.Position.X, math.clamp(math.lerp(suspensionStartCenterDist[wheelAtt], springCompressionDist, i / simulationSteps) - settings.SuspensionRange, -settings.SuspensionRange, settings.SuspensionRange), wheelAtt.Position.Z)
			
			simulationChassisVelocity += springForce / simulationChassisMass * SIMULATION_DT  -- m * dv = SF * dt | dv = SF / m * dt
			
			if DEBUG then SimulationDebug:DebugVector(simulationChassisCFrame:PointToWorldSpace(wheelAtt.Position), springForce, DEBUG_COLOR_FORCE, wheelAtt:GetAttribute("DebugWheelName"), springSprungMassForce) end
			if DEBUG then SimulationDebug:DebugContact(ChassisPhysics:PositionRaycast(wheelAtt.WorldPosition, simulationChassisCFrame.UpVector * SIMULATION_RAYCASTLENGTH), DEBUG_COLOR_CONTACT, wheelAtt:GetAttribute("DebugWheelName").." contact") end
		end 
		
		simulationChassisRotation += simulationChassisAngularVelocity * SIMULATION_DT
		simulationChassisPosition += simulationChassisVelocity * SIMULATION_DT
		simulationChassisCFrame = CFrame.new(simulationChassisPosition) * CFrame.Angles(simulationChassisRotation.X * MATH_DEG2RAD, simulationChassisRotation.Y * MATH_DEG2RAD, simulationChassisRotation.Z * MATH_DEG2RAD)
		
		if DEBUG then SimulationDebug:DebugStep(chassis, simulationChassisCFrame, simulationChassisVelocity) end
	end
	
	if DEBUG then SimulationDebug:DebugEnd(chassis) end
	
	return {}
end


-- Init
local function Init()
	SimulationDebug:Init()
end

Init()


return ChassisPhysics
