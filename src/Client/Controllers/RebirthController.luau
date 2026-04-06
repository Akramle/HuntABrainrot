local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))
local ViewportHelper = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ViewportHelper"))

local RebirthController = {
	Name = "RebirthController",
	Priority = 20,
}

function RebirthController:Init(runtime)
	self._runtime = runtime
	self._config = runtime.Config
	self._player = Players.LocalPlayer
	self._remote = runtime.Remotes:GetRebirthRemote()
	self._updateQueued = false
	self._lastAnimalsSignature = nil
end

local function isPartVisible(part: BasePart): boolean
	if part.Transparency < 0.95 then
		return true
	end

	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Decal") or child:IsA("Texture") or child:IsA("DataModelMesh") then
			return true
		end
	end

	return false
end

function RebirthController:_collectOwnedAnimals(): {[string]: boolean}
	local owned = {}
	local backpack = self._player:FindFirstChild("Backpack")
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if CollectionService:HasTag(item, "Animal") then
				owned[item.Name] = true
			end
		end
	end
	
	local char = self._player.Character
	if char then
		for _, item in ipairs(char:GetChildren()) do
			if CollectionService:HasTag(item, "Animal") then
				owned[item.Name] = true
			end
		end
	end

	local baseFolder = workspace:FindFirstChild("Bases")
	local playerBase = baseFolder and baseFolder:FindFirstChild(self._player.Name)
	if playerBase then
		for _, desc in ipairs(playerBase:GetDescendants()) do
			if CollectionService:HasTag(desc, "Animal") then
				owned[desc.Name] = true
			end
		end
	end

	return owned
end

function RebirthController:_tintBlack(model, transparency)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			if not isPartVisible(part) then
				continue
			end
			part.Color = Color3.new(0, 0, 0)
			part.Material = Enum.Material.Neon
			if transparency then part.Transparency = transparency end
			
			if part:IsA("MeshPart") then
				part.TextureID = ""
				local sa = part:FindFirstChildWhichIsA("SurfaceAppearance")
				if sa then sa:Destroy() end
			end
		elseif part:IsA("SpecialMesh") then
			part.TextureId = ""
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = 1
		end
	end
end

function RebirthController:_setupAnimalViewport(viewport, animalName, isOwned)
	local templates = ReplicatedStorage:FindFirstChild("AdminAnimalTemplates")
	local template = nil
	if templates then
		for _, rarityFolder in ipairs(templates:GetChildren()) do
			template = rarityFolder:FindFirstChild(animalName)
			if template then break end
		end
	end

	if not template then return end

	local _, displayClone = ViewportHelper.SetupViewport(viewport, template, {
		FieldOfView = 12,
		Zoom = 1.5
	})

	-- Black if NOT owned (requirement not met), normal if owned
	if not isOwned and displayClone then
		self:_tintBlack(displayClone, 0)
	end
end

function RebirthController:UpdateUI()
	local playerGui = self._player:FindFirstChild("PlayerGui")
	local main = playerGui and playerGui:FindFirstChild("Main")
	local tabs = main and main:FindFirstChild("Tabs")
	local rebirthTab = tabs and tabs:FindFirstChild("Rebirth")
	if not rebirthTab then return end

	local requirementsFrame = rebirthTab:FindFirstChild("Requirements")
	if not requirementsFrame then return end

	local animalTemplate = requirementsFrame:FindFirstChild("AnimalTemplate")
	local bucksTemplate = requirementsFrame:FindFirstChild("BucksTemplate")
	local diamondsTemplate = requirementsFrame:FindFirstChild("DiamondsTemplate") or requirementsFrame:FindFirstChild("DiamondTemplate")
	if not diamondsTemplate then
		for _, child in ipairs(requirementsFrame:GetChildren()) do
			if string.find(child.Name:lower(), "diamond") then
				diamondsTemplate = child
				break
			end
		end
	end
	
	local rebirthBtnFrame = rebirthTab:FindFirstChild("RebirthBtn")
	local rebirthBtn = rebirthBtnFrame and rebirthBtnFrame:FindFirstChild("btn")

	local leaderstats = self._player:FindFirstChild("leaderstats")
	if not leaderstats then return end
	
	local rebirthsVal = leaderstats:FindFirstChild("Rebirths")
	if not rebirthsVal then return end
	local currentRebirths = rebirthsVal.Value
	
	local requirements = self._config.Rebirth and self._config.Rebirth.Requirements
	if not requirements then return end
	
	local req = nil
	for _, r in ipairs(requirements) do
		if r.RebirthCount == currentRebirths then
			req = r
			break
		end
	end
	if not req then req = requirements[#requirements] end
	if not req then return end
	local ownedAnimals = self:_collectOwnedAnimals()

	-- 1. Initial State: Hide currency templates
	if bucksTemplate then bucksTemplate.Visible = false end
	if diamondsTemplate then diamondsTemplate.Visible = false end

	-- 2. Update Bucks
	local requiredBucks = tonumber(req.Bucks) or 0
	if bucksTemplate and requiredBucks > 0 then
		bucksTemplate.Visible = true
		bucksTemplate.amount.Text = NumberFormatter:Format(requiredBucks, "Letters")
		local bucksVal = leaderstats:FindFirstChild("Bucks")
		local currentBucks = bucksVal and bucksVal.Value or 0
		local isDone = currentBucks >= requiredBucks
		local doneIcon = bucksTemplate:FindFirstChild("done")
		if doneIcon then doneIcon.Visible = isDone end
	end

	-- 3. Update Diamonds
	local requiredDiamonds = tonumber(req.Diamonds) or 0
	if diamondsTemplate and requiredDiamonds > 0 then
		diamondsTemplate.Visible = true
		diamondsTemplate.amount.Text = NumberFormatter:Format(requiredDiamonds, "Letters")
		local diamondsVal = leaderstats:FindFirstChild("Diamonds")
		local currentDiamonds = diamondsVal and diamondsVal.Value or 0
		local isDone = currentDiamonds >= requiredDiamonds
		local doneIcon = diamondsTemplate:FindFirstChild("done")
		if doneIcon then doneIcon.Visible = isDone end
	end

	-- 4. Update Animals (Multi-handling)
	if animalTemplate then
		animalTemplate.Visible = false -- Hide source

		local animalSignature = tostring(currentRebirths)
		if req.Animals then
			local signatureParts = {}
			for _, animalName in ipairs(req.Animals) do
				table.insert(signatureParts, animalName .. ":" .. (ownedAnimals[animalName] and "1" or "0"))
			end
			animalSignature = animalSignature .. "|" .. table.concat(signatureParts, ",")
		end

		if animalSignature ~= self._lastAnimalsSignature then
			self._lastAnimalsSignature = animalSignature
			for _, child in ipairs(requirementsFrame:GetChildren()) do
				if child:GetAttribute("IsAnimalClone") then
					child:Destroy()
				end
			end
			if req.Animals then
				for _, animalName in ipairs(req.Animals) do
					local clone = animalTemplate:Clone()
					clone.Name = "Animal_" .. animalName
					clone:SetAttribute("IsAnimalClone", true)
					
					local nameLabel = clone:FindFirstChild("name")
					if nameLabel then nameLabel.Text = animalName end
					
					local isOwned = ownedAnimals[animalName] == true
					local viewport = clone:FindFirstChild("ViewportFrame")
					if viewport then
						self:_setupAnimalViewport(viewport, animalName, isOwned)
					end
					
					local doneIcon = clone:FindFirstChild("done")
					if doneIcon then doneIcon.Visible = isOwned end
					
					clone.Visible = true
					clone.Parent = requirementsFrame
				end
			end
		end
	end
	
	-- Connect Rebirth Button if not already
	if rebirthBtn and not rebirthBtn:GetAttribute("Connected") then
		rebirthBtn:SetAttribute("Connected", true)
		rebirthBtn.MouseButton1Click:Connect(function()
			self._remote:FireServer("Rebirth")
		end)
	end
end

function RebirthController:_queueUpdate()
	if self._updateQueued then return end
	self._updateQueued = true
	task.delay(0.1, function()
		self._updateQueued = false
		self:UpdateUI()
	end)
end

function RebirthController:Start()
	-- TabController will handle the binding of the RebirthBtn to Rebirth tab.
	-- We just need to update the content when it opens.
	
	local playerGui = self._player:WaitForChild("PlayerGui")
	local main = playerGui:WaitForChild("Main")
	local tabs = main:WaitForChild("Tabs")
	local rebirthTab = tabs:WaitForChild("Rebirth", 10)
	
	if rebirthTab then
		rebirthTab:GetPropertyChangedSignal("Visible"):Connect(function()
			if rebirthTab.Visible then
				self:_queueUpdate()
			end
		end)
	end

	-- Also update when stats change if visible
	local leaderstats = self._player:WaitForChild("leaderstats")
	local function bindStat(name)
		local stat = leaderstats:WaitForChild(name, 10)
		if stat then
			stat.Changed:Connect(function()
				if rebirthTab and rebirthTab.Visible then
					self:_queueUpdate()
				end
			end)
		end
	end
	bindStat("Bucks")
	bindStat("Diamonds")
	bindStat("Rebirths")

	local function bindContainer(container)
		if not container then return end
		container.ChildAdded:Connect(function()
			if rebirthTab and rebirthTab.Visible then
				self:_queueUpdate()
			end
		end)
		container.ChildRemoved:Connect(function()
			if rebirthTab and rebirthTab.Visible then
				self:_queueUpdate()
			end
		end)
	end

	local backpack = self._player:FindFirstChild("Backpack")
	bindContainer(backpack)
	self._player.ChildAdded:Connect(function(child)
		if child.Name == "Backpack" then
			bindContainer(child)
		end
	end)
	self._player.CharacterAdded:Connect(function(character)
		bindContainer(character)
		if rebirthTab and rebirthTab.Visible then
			self:_queueUpdate()
		end
	end)
end

return RebirthController
