-- Services
local uisService = game:GetService("UserInputService")
local rn = game:GetService("RunService")


-- Constants
local SIMULATION_TARGETSTEPS: number = 240   			  -- Hz
local SIMULATION_DT: number = 1 / SIMULATION_TARGETSTEPS  -- s
local SIMULATION_RAYCASTLENGTH: number = -100
local SIMULATION_RAYCASTMAXDISTANCE: number = 100

local DEBUG: boolean = false
local DEBUG_NOSTEP: boolean = false
local DEBUG_STEPKEYTHROTTLED: boolean = true
local DEBUG_STEPKEY: Enum.KeyCode = Enum.KeyCode.Return
local DEBUG_LOGDECIMALS: number = 2
local DEBUG_HIGHLIGHT_FILLTRANSPARENCY: number = 0.5

local DEBUG_COLOR_OBJECT: Color3 = Color3.fromRGB(255, 255, 0)
local DEBUG_COLOR_OBJECTSTART: Color3 = Color3.fromRGB(0, 255, 0)
local DEBUG_COLOR_FORCE: Color3 = Color3.fromRGB(255, 0, 0)
local DEBUG_COLOR_TORQUE: Color3 = Color3.fromRGB(127, 0, 255)
local DEBUG_COLOR_VELOCITY: Color3 = Color3.fromRGB(0, 255, 255)
local DEBUG_COLOR_CONTACT: Color3 = Color3.fromRGB(255, 0, 255)

local CHASSISPHYSICS_RAYCASTPARAMS: RaycastParams = RaycastParams.new()
CHASSISPHYSICS_RAYCASTPARAMS.FilterType = Enum.RaycastFilterType.Exclude
CHASSISPHYSICS_RAYCASTPARAMS.IgnoreWater = true
CHASSISPHYSICS_RAYCASTPARAMS.RespectCanCollide = true

local MATH_DEG2RAD: number = math.rad(1)
local MATH_RAD2DEG: number = math.deg(1)
local MATH_STUDS2METERS: number = 0.28



-- static class SimulationDebug
type SimulationDebug = {
	DebugFolder: Folder,
	DebugChassisPrediction: Part,
	DebugChassisEnd: Part,
	DebugForces: {Part},

	DebugSimulationIteration: number,
	DebugStepKeyPressed: boolean,

	ToString: (number, number) -> string,

	Init: () -> (),
	DebugLog: (string) -> (),
	DebugStart: (Model, {[Attachment]: Vector3}) -> (),
	DebugVector: (Vector3, Vector3, Color3?, string?, number?) -> (),
	DebugContact: (Vector3, Color3?, string?) -> (),
	DebugStep: (Model, CFrame, Vector3) -> (),
	DebugEnd: (Model, CFrame) -> ()
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
	self.DebugChassisPrediction.Color = DEBUG_COLOR_OBJECT
	self.DebugChassisPrediction.Anchored = true
	self.DebugChassisPrediction.CanCollide = false
	self.DebugChassisPrediction.CanQuery = false
	self.DebugChassisPrediction.Size = Vector3.new(9, 1.182, 20)
	self.DebugChassisPrediction.Transparency = 0.5

	self.DebugChassisEnd = Instance.new("Part", self.DebugFolder)
	self.DebugChassisEnd.Name = "SimulationChassisEnd"
	self.DebugChassisEnd.Color = DEBUG_COLOR_OBJECTSTART
	self.DebugChassisEnd.Anchored = true
	self.DebugChassisEnd.CanCollide = false
	self.DebugChassisEnd.CanQuery = false
	self.DebugChassisEnd.Size = Vector3.new(9, 1.182, 20)
	self.DebugChassisEnd.Transparency = 0.5

	self.DebugSimulationIteration = 0
end


function SimulationDebug:DebugLog(message: string): nil
	if DEBUG_NOSTEP then return end

	warn(message)
end


function SimulationDebug:DebugStart(chassis: Model): nil
	chassis.Engine.Anchored = true

	self.DebugSimulationIteration += 1

	if DEBUG_NOSTEP then
		-- Debug: Cleanup
		for _, debugPart: part in self.DebugFolder:GetChildren() do
			if debugPart:GetAttribute("DebugPart") ~= true then continue end

			debugPart:Destroy()
		end
	end

	self:DebugLog(`--- Simulation #{self.DebugSimulationIteration} ---`)
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

	self:DebugLog(`{label.. " | " or ""} [{self:ToString(direction.X, DEBUG_LOGDECIMALS)}, {self:ToString(direction.Y, DEBUG_LOGDECIMALS)}, {self:ToString(direction.Z, DEBUG_LOGDECIMALS)}]`)
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

	-- self:DebugLog(`{label.. " | " or ""} [{self:ToString(origin.X, DEBUG_LOGDECIMALS)}, {self:ToString(origin.Y, DEBUG_LOGDECIMALS)}, {self:ToString(origin.Z, DEBUG_LOGDECIMALS)}]`)
end


function SimulationDebug:DebugStep(chassis: Model, chassisCFramePrediction: CFrame, chassisPredictedVelocity: Vector3): nil
	self.DebugChassisPrediction.CFrame = chassisCFramePrediction

	self:DebugVector(chassisCFramePrediction.Position, chassisPredictedVelocity, DEBUG_COLOR_VELOCITY, "Predicted velocity")

	local stepKeyPressedToggle: boolean = uisService:IsKeyDown(DEBUG_STEPKEY)

	if DEBUG_NOSTEP then return end

	while true do 
		rn.PreSimulation:Wait()

		local stepKeyPressed: boolean = uisService:IsKeyDown(DEBUG_STEPKEY)

		self.DebugStepKeyPressed = self.DebugStepKeyPressed == false and stepKeyPressed and stepKeyPressed ~= stepKeyPressedToggle
		stepKeyPressedToggle = stepKeyPressed

		if DEBUG_STEPKEYTHROTTLED == false and stepKeyPressed or self.DebugStepKeyPressed then break end
	end

	-- Debug: Cleanup
	for _, debugPart: part in self.DebugFolder:GetChildren() do
		if debugPart:GetAttribute("DebugPart") ~= true then continue end

		debugPart:Destroy()
	end
end


function SimulationDebug:DebugEnd(chassis: Model, predictedCFrame: CFrame): nil
	chassis.Engine.Anchored = false

	self.DebugChassisEnd.CFrame = predictedCFrame
end


-- struct Matrix3
type Matrix3 = {
	x1: number, y1: number, z1: number,
	x2: number, y2: number, z2: number,
	x3: number, y3: number, z3: number,

	Transpose: () -> Matrix3,
	Inverse: () -> Matrix3
}

local Matrix3 = {}


function Matrix3:Transpose(): Matrix3
	return Matrix3:New(self.x1, self.x2, self.x3,
		self.y1, self.y2, self.y3,
		self.z1, self.z2, self.z3)
end


function Matrix3:Inverse(): Matrix3
	local iDet: number = 1 / (self.x1 * self.y2 * self.z3  -- This can yield a divide by zero!
		+ self.y1 * self.z2 * self.x3
		+ self.z1 * self.x2 * self.y3
		- self.z1 * self.y2 * self.x3
		- self.y1 * self.x2 * self.z3
		- self.x1 * self.z2 * self.y3)

	return Matrix3:New(self.y2*self.z3 - self.z2*self.y3, self.z2*self.x3 - self.x2*self.z3, self.x2*self.y3 - self.y2*self.x3,
		self.y3*self.z1 - self.z3*self.y1, self.z3*self.x1 - self.x3*self.z1, self.x3*self.y1 - self.y3*self.x1,
		self.y1*self.z2 - self.z1*self.y2, self.z1*self.x2 - self.x1*self.z2, self.x1*self.y2 - self.y1*self.x2):Transpose() * iDet
end


local Matrix3MT = {
	__index = Matrix3,
	__add = function(self: Matrix3, other: Matrix3)
		self.x1 += other.x1
		self.y1 += other.y1
		self.z1 += other.y1

		self.x2 += other.x2
		self.y2 += other.y2
		self.z2 += other.z2

		self.x3 += other.x3
		self.y3 += other.y3
		self.z3 += other.z3

		return self
	end,
	__div = function(other: Vector3, self: Matrix3)
		local inverseMatrix: Matrix3 = self:Inverse()

		return inverseMatrix * other
	end,
	__mul = function(self: Matrix3, other: number | Vector3 | Matrix3)
		if typeof(other) == "number" then
			self.x1 *= other
			self.y1 *= other
			self.z1 *= other

			self.x2 *= other
			self.y2 *= other
			self.z2 *= other

			self.x3 *= other
			self.y3 *= other
			self.z3 *= other

			return self
		elseif typeof(other) == "Vector3" then
			return Vector3.new(self.x1 * other.X + self.y1 * other.Y + self.z1 * other.Z,
				self.x2 * other.X + self.y2 * other.Y + self.z2 * other.Z,
				self.x3 * other.X + self.y3 * other.Y + self.z3 * other.Z)
		end
	end
}

function Matrix3:New(x1: number, y1: number, z1: number, x2: number, y2: number, z2: number, x3: number, y3: number, z3: number): Matrix3
	local self = setmetatable({}, Matrix3MT)

	self.x1 = x1
	self.y1 = y1
	self.z1 = z1

	self.x2 = x2
	self.y2 = y2
	self.z2 = z2

	self.x3 = x3
	self.y3 = y3
	self.z3 = z3

	return self
end


-- Math static class
type Math = {
	FromDiagonal: (Vector3) -> Matrix3,
	ToDiagonal: (Matrix3) -> Vector3,
	MulMatrixDiagVector: (Matrix3, Vector3) -> Matrix3,
	MulMatrixMatrixTranspose: (Matrix3, Matrix3) -> Matrix3
}

local Math: Math = {}

function Math.FromDiagonal(v: Vector3): Matrix3
	return Matrix3:New(v.X, 0.0, 0.0,
		0.0, v.Y, 0.0,
		0.0, 0.0, v.z)
end

function Math.ToDiagonal(mat: Matrix3): Vector3
	return Vector3.new(mat.x1, mat.y2, mat.z3)
end

function Math.MulMatrixDiagVector(mat: Matrix3, v: Vector3): Matrix3
	return Matrix3:New(mat.x1 * v.X, mat.y1 * v.Y, mat.z1 * v.Z,
		mat.x2 * v.X, mat.y2 * v.Y, mat.z2 * v.Z,
		mat.x3 * v.X, mat.y3 * v.Y, mat.z3 * v.Z)
end

function Math.MulMatrixMatrixTranspose(m0: Matrix3, m1: Matrix3): Matrix3
	return Matrix3:New(
		-- iRow = 0
		m0.x1 * m1.x1 +
			m0.y1 * m1.y1 +
			m0.z1 * m1.z1,

		m0.x1 * m1.x2 +
			m0.y1 * m1.y2 +
			m0.z1 * m1.z2,

		m0.x1 * m1.x3 +
			m0.y1 * m1.y3 +
			m0.z1 * m1.z3,
		-- iRow = 1
		m0.x2 * m1.x1 +
			m0.y2 * m1.y1 +
			m0.z2 * m1.z1,

		m0.x2 * m1.x2 +
			m0.y2 * m1.y2 +
			m0.z2 * m1.z2,

		m0.x2 * m1.x3 +
			m0.y2 * m1.y3 +
			m0.z2 * m1.z3,
		-- iRow = 2
		m0.x3 * m1.x1 +
			m0.y3 * m1.y1 +
			m0.z3 * m1.z1,

		m0.x3 * m1.x2 +
			m0.y3 * m1.y2 +
			m0.z3 * m1.z2,

		m0.x3 * m1.x3 +
			m0.y3 * m1.y3 +
			m0.z3 * m1.z3)
end


-- class Rigidbody
type Rigidbody = {
	Mass: number,
	Size: Vector3,
	Cofm: Vector3,
	Position: Vector3,
	LinearVelocity: Vector3,
	AngularVelocity: Vector3,
	CFrame: CFrame,
	RotationMatrix: Matrix3,

	InertiaTensor: Matrix3,
	CofmMOI: Vector3,
	MomentRecipWorld: Matrix3,
	LinearMomentum: Vector3,
	AngMomentum: Vector3,

	GetInertiaTensor: () -> Matrix3,
	GetIBodyAtPosition: (Vector3) -> Matrix3,
	GetLinearVelocity: () -> Vector3,
	GetAngularVelocity: () -> Vector3,
	GetRotationMatrix: () -> Matrix3,
	ApplyImpulse: (Vector3) -> (),
	ApplyImpulseAtPosition: (Vector3, Vector3) -> (),
	Step: (number) -> ()
}

local Rigidbody = {}


function Rigidbody:GetInertiaTensor(): Matrix3
	local size: {number} = {self.Size.X, self.Size.Y, self.Size.Z}
	local area: number = 2 * (self.Size.x*self.Size.y + self.Size.y*self.Size.z + self.Size.z*self.Size.x)
	local I: {number} = {}

	for i = 1, 3 do  -- TODO: Check if correct, modified to accomodate 1-3 instead of 0-2
		local j: number = i % 3 + 1;
		local k: number = (i + 1) % 3 + 1;
		local x: number = size[i];
		local y: number = size[j];
		local z: number = size[k];

		I[i] = (self.Mass / (2.0 * area)) * ((y*y*y*z/3.0)
			+	(y*z*z*z/3.0)
			+	(x*y*z*z)
			+	(x*y*y*y/3.0)
			+	(x*y*y*z)
			+	(x*z*z*z/3.0))
	end

	return Math.FromDiagonal(Vector3.new(I[1], I[2], I[3]));
end


function Rigidbody:GetIBodyAtPosition(relativePosition: Vector3): Matrix3
	-- TODO: Check if the relative position is supposed to be in object space
	local x2: number = relativePosition.x * relativePosition.x;
	local y2: number = relativePosition.y * relativePosition.y;
	local z2: number = relativePosition.z * relativePosition.z;
	local xy: number = relativePosition.x * relativePosition.y;
	local xz: number = relativePosition.x * relativePosition.z;
	local yz: number = relativePosition.y * relativePosition.z;

	return self.InertiaTensor + Matrix3:New(y2 + z2, -xy,     -xz,
		-xy,     x2 + z2, -yz,
		-xz,     -yz,     x2 + y2) * self.Mass
end


function Rigidbody:GetLinearVelocity(): Vector3
	return self.LinearMomentum / self.Mass
end


function Rigidbody:GetAngularVelocity(): Vector3
	return self.MomentRecipWorld * self.AngularMomentum
end


function Rigidbody:GetRotationMatrix(): Matrix3
	local x, y, z, rx1, ry1, rz1, rx2, ry2, rz2, rx3, ry3, rz3 = self.CFrame:GetComponents()

	return Matrix3:New(rx1, ry1, rz1,
		rx2, ry2, rz2,
		rx3, ry3, rz3)
end


function Rigidbody:ApplyImpulse(impulse: Vector3): nil
	self.LinearMomentum += impulse

	self.LinearVelocity = self:GetLinearVelocity()
end


function Rigidbody:ApplyImpulseAtPosition(impulse: Vector3, worldPosition: Vector3): nil
	local relativeWorldPosition: Vector3 = worldPosition - self.Position

	self.LinearMomentum += impulse
	self.AngularMomentum *= 0.9998   -- Angular momentum damping
	self.AngularMomentum += relativeWorldPosition:Cross(impulse)

	self.LinearVelocity = self:GetLinearVelocity()
	self.AngularVelocity = self:GetAngularVelocity()
end


function Rigidbody:Step(deltaTime: number): nil
	self.AngularMomentum *= 0.99621  -- Angular momentum damping (0.9998^19)
	self.AngularVelocity = self:GetAngularVelocity()

	self.Position += self.LinearVelocity * deltaTime
	self.CFrame += self.LinearVelocity * deltaTime

	if self.AngularVelocity.Magnitude > 0 then
		self.CFrame = (CFrame.fromAxisAngle(self.AngularVelocity.Unit, self.AngularVelocity.Magnitude * deltaTime) * self.CFrame.Rotation) + self.Position
	end

	self.RotationMatrix = self:GetRotationMatrix()

	self.MomentRecipWorld = Math.MulMatrixMatrixTranspose(Math.MulMatrixDiagVector(self.RotationMatrix, Vector3.new(1, 1, 1) / self.CofmMOI), self.RotationMatrix)
end


function Rigidbody:New(referencePart: BasePart): Rigidbody
	local self = setmetatable({}, {__index = Rigidbody})

	self.Mass = referencePart.AssemblyMass
	self.Size = referencePart.Size
	self.Cofm = referencePart.CFrame:ToObjectSpace(CFrame.new(referencePart.AssemblyCenterOfMass))
	self.Position = referencePart.Position
	self.LinearVelocity = referencePart.AssemblyLinearVelocity
	self.AngularVelocity = referencePart.AssemblyAngularVelocity
	self.CFrame = referencePart.CFrame
	self.RotationMatrix = self:GetRotationMatrix()

	self.InertiaTensor = self:GetInertiaTensor()
	self.CofmMOI = Math.ToDiagonal(self:GetIBodyAtPosition(self.Cofm))
	self.MomentRecipWorld = Math.MulMatrixMatrixTranspose(Math.MulMatrixDiagVector(self.RotationMatrix, Vector3.new(1, 1, 1) / self.CofmMOI), self.RotationMatrix)

	self.LinearMomentum = self.Mass * self.LinearVelocity
	self.AngularMomentum = Math.MulMatrixMatrixTranspose(Math.MulMatrixDiagVector(self.RotationMatrix, self.CofmMOI), self.RotationMatrix) * self.AngularVelocity

	return self
end


-- struct SubstepResult
type SubstepResult = {
	CFrames: {CFrame},
	Impulses: {{{Position: Vector3, Impulse: Vector3}}},
	SuspensionY: {[Attachment]: number},

	AddImpulse: (CFrame, Vector3, Vector3) -> (),
	New: (Vector3, Vector3) -> {}
}

local SubstepResult = {}

function SubstepResult:AddImpulse(cframe: CFrame, position: Vector3, impulse: Vector3)
	if not table.find(self.CFrames, cframe) then table.insert(self.CFrames, cframe); table.insert(self.Impulses, {}) end

	local cframeIndex = table.find(self.CFrames, cframe)

	table.insert(self.Impulses[cframeIndex], {Position = position, Impulse = impulse})
end 

function SubstepResult:New(): SubstepResult
	local self = setmetatable({}, {__metatable = "Locked", __index = SubstepResult})

	self.CFrames = {}
	self.Impulses = {}
	self.SuspensionY = {}

	return self
end


-- static class ChassisPhysics
local ChassisPhysics = {}


-- Raycast hit distance helper function
local function DistanceRaycast(origin: Vector3, direction: Vector3): number
	local result: RaycastResult = workspace:Raycast(origin, direction, CHASSISPHYSICS_RAYCASTPARAMS)

	return result and result.Distance or SIMULATION_RAYCASTMAXDISTANCE
end


-- Raycast hit position helper function
local function PositionRaycast(origin: Vector3, direction: Vector3): Vector3
	local result: RaycastResult = workspace:Raycast(origin, direction, CHASSISPHYSICS_RAYCASTPARAMS)

	return result and result.Position or origin + direction
end


-- Physics helper functions
-- // Absolute velocity (ω x r + v)
local function GetVelocityAtPoint(relativeWorldPosition: Vector3, angularVelocity: Vector3, velocity: Vector3): Vector3
	return angularVelocity:Cross(relativeWorldPosition) + velocity
end 


-- // MMOI helper function (Source: https://devforum.roblox.com/t/vectorforce-suspension-unstable/3150586/30)
local function GetMMOI(mass: number, size: Vector3, axisOfRotation: Vector3): number
	-- MMOI: Calculate moment of inertia along the arbitrary axis
	return (axisOfRotation.X * (axisOfRotation.X * mass * (size.Y^2 + size.Z^2) / 12 + 0 + 0) +
		axisOfRotation.Y * (0 + axisOfRotation.Y * mass * (size.X^2 + size.Z^2) / 12 + 0) +
		axisOfRotation.Z * (0 + 0 + axisOfRotation.Z * mass * (size.X^2 + size.Y^2) / 12))
end


-- ChassisPhysics raycast params helper function
function ChassisPhysics:SetTargetChassis(chassis: Model)
	CHASSISPHYSICS_RAYCASTPARAMS.FilterDescendantsInstances = {chassis}
end


-- Simulates, estimates, and calculates in-between frames the car's next traction, suspension, and steering values using PACJKA's magic formula
function ChassisPhysics:SubstepSimulation(chassis: Model, control: {Hold: boolean, Brake: number, BrakeAmt: number, Forward: number}, settings: {Height: number, SuspensionDampeningRatio: number, SuspensionRange: number, Grip: number}, frameTime: number): SubstepResult
	local substepResults: SubstepResult = SubstepResult:New()

	if chassis.Engine.Anchored then return substepResults end  -- Avoids simulating if the vehicle is anchored, preventing NaNs

	local engine: BasePart = chassis.Engine :: BasePart
	local wheelsAtts: {Attachment} = engine:GetChildren()

	-- Simulation: Initialize
	local simulationSteps: number = math.floor(frameTime / SIMULATION_DT)  -- Scales the current frame time into a number of whole substeps
	local simulationRigidbody: Rigidbody = Rigidbody:New(engine)

	-- Force: Spring
	local springSprungMassForce: number = simulationRigidbody.Mass * workspace.Gravity / #wheelsAtts
	local springStiffness: number = springSprungMassForce / settings.SuspensionRange
	local springDamper: number = settings.SuspensionDampeningRatio * 2 * math.sqrt(springStiffness * simulationRigidbody.Mass)
	local springSuspensionY: {[Attachment]: number} = {}

	for _, wheelAtt: Attachment in wheelsAtts do
		springSuspensionY[wheelAtt] = wheelAtt.Position.Y
	end

	-- Force: Traction and Grip
	local gripValue = settings.Grip

	-- Speed-based PACJKA Steering Stiffness Adjustment (using PACJKA's magic formula)
	local vehicleSpeed = simulationRigidbody.LinearVelocity.Magnitude
	local maxSpeed = settings.MaxSpeed  -- Max speed (you can adjust this value based on your car's characteristics)

	-- Parameters for PACJKA magic formula (can be adjusted for realism)
	local B = 12  -- Stiffness factor, controls how steeply the steering response increases with slip angle
	local C = 1.3  -- Curvature, adjusts how much the steering curve is compressed/expanded
	local D = 1.0  -- Maximum value, scaling the force output
	local E = 0.97 -- Shape factor, adjusts the non-linearity of the curve

	-- PACJKA formula for steering response based on speed (influences B, C)
	local steeringStiffness = math.clamp(D * math.sin(C * math.atan(B * vehicleSpeed / maxSpeed)), 0.3, 1.0)

	-- Simulation: Simulate and estimate
	for i = 1, simulationSteps do

		-- Apply forces to simulate
		simulationRigidbody:ApplyImpulse(-Vector3.yAxis * simulationRigidbody.Mass * workspace.Gravity * SIMULATION_DT)

		-- // Traction values and Lock-Up Condition
		

		-- Simulation: Suspension springs and wheel traction
		for _, wheelAtt: Attachment in wheelsAtts do
			local simulationWheelCFrame: CFrame = simulationRigidbody.CFrame * CFrame.new(wheelAtt.Position) * CFrame.Angles(wheelAtt.Orientation.X * MATH_DEG2RAD, wheelAtt.Orientation.Y * MATH_DEG2RAD, wheelAtt.Orientation.Z * MATH_DEG2RAD)

			-- // Suspension spring
			local simulationWheelPosition: Vector3 = simulationRigidbody.CFrame:PointToWorldSpace(wheelAtt.Position)
			local simulationWheelRelativePosition: Vector3 = simulationWheelPosition - simulationRigidbody.Position

			local springUpperLimitPosition: Vector3 = simulationRigidbody.CFrame:PointToWorldSpace(Vector3.new(wheelAtt.Position.X, settings.SuspensionRange, wheelAtt.Position.Z))
			local springSurfaceContactDist: number = DistanceRaycast(springUpperLimitPosition, simulationRigidbody.CFrame.UpVector * SIMULATION_RAYCASTLENGTH)
			local springCompressionDist: number = 2 * settings.SuspensionRange - math.clamp(springSurfaceContactDist - 0.5 * wheelAtt.Wheel.Size.Y, 0, 2 * settings.SuspensionRange)
			local springContactSpeed: number = math.clamp((springCompressionDist - settings.SuspensionRange - springSuspensionY[wheelAtt]) / SIMULATION_DT, -10, 10)
			local springForce: Vector3 = simulationRigidbody.CFrame.UpVector * math.clamp(springStiffness * springCompressionDist + springContactSpeed * springDamper, 0, math.huge)

			-- Apply suspension forces
			simulationRigidbody:ApplyImpulseAtPosition(springForce * SIMULATION_DT, simulationWheelPosition)
			substepResults:AddImpulse(simulationRigidbody.CFrame, simulationWheelPosition, springForce * SIMULATION_DT)

			springSuspensionY[wheelAtt] = springCompressionDist - settings.SuspensionRange
		end

		-- Simulation: Step end
		simulationRigidbody:Step(SIMULATION_DT)
		substepResults.SuspensionY = springSuspensionY
	end

	return substepResults
end

-- Init
local function Init()
	SimulationDebug:Init()
end

Init()

return ChassisPhysics
