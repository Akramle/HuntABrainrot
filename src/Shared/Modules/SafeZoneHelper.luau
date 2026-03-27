local CollectionService = game:GetService("CollectionService")

local SafeZoneHelper = {}

-- Cache safe zone parts for fast point-in-AABB checks.
local _zones: {BasePart} = {}

local function refreshCache()
	_zones = {}
	for _, z in ipairs(CollectionService:GetTagged("SafeZone")) do
		if z and z:IsA("BasePart") then
			table.insert(_zones, z)
		end
	end
end

refreshCache()

CollectionService:GetInstanceAddedSignal("SafeZone"):Connect(function(inst)
	if inst and inst:IsA("BasePart") then
		table.insert(_zones, inst)
	end
end)

CollectionService:GetInstanceRemovedSignal("SafeZone"):Connect(function(inst)
	if not inst or not inst:IsA("BasePart") then
		return
	end

	for i = #_zones, 1, -1 do
		if _zones[i] == inst then
			table.remove(_zones, i)
			return
		end
	end
end)

local function pointInsidePart(part: BasePart, worldPos: Vector3): boolean
	-- Convert world point into the part's local space and do an AABB check.
	local localPos = part.CFrame:PointToObjectSpace(worldPos)
	local half = part.Size * 0.5
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

function SafeZoneHelper.isInSafeZone(worldPos: Vector3): boolean
	if typeof(worldPos) ~= "Vector3" then
		return false
	end

	for _, z in ipairs(_zones) do
		if z and z.Parent ~= nil and pointInsidePart(z, worldPos) then
			return true
		end
	end

	return false
end

return SafeZoneHelper

