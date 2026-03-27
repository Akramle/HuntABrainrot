local NumberFormatter = {}

-- Suffixes map to powers of 1000: K=10^3, M=10^6, ..., SP=10^24
local suffixes = {"K", "M", "B", "T", "Qa", "Qi", "Sx", "SP", "Oc", "No", "Dc"}

-- Helper function to format numbers with letters
local function formatLetters(value)
	local num = tonumber(value)
	if not num then return value end

	-- Return normal number if it's less than 1,000
	-- Use string.format to avoid long floating point decimals (e.g. 0.30000000000004 -> 0.3)
	if math.abs(num) < 1000 then 
		return string.format("%.1f", num):gsub("%.?0+$", "")
	end

	-- Calculate the suffix index based on the power of 1000
	local suffixIndex = math.floor(math.log10(math.abs(num)) / 3)

	-- Cap the index to the maximum available suffix in our list
	if suffixIndex > #suffixes then
		suffixIndex = #suffixes
	end

	-- Calculate the abbreviated number
	local displayValue = num / (10 ^ (suffixIndex * 3))

	-- Format to 2 decimal places, then strip any unnecessary trailing zeros and the decimal point
	local formattedString = string.format("%.2f", displayValue):gsub("%.?0+$", "")

	return formattedString .. suffixes[suffixIndex]
end

-- Helper function to format numbers with commas
local function formatComma(value)
	local num = tonumber(value)
	if not num then return value end

	-- Use string manipulation to insert commas every 3 digits
	local left, numberPart, right = string.match(tostring(num), '^([^%d]*%d)(%d*)(.-)$')
	if not left then return tostring(num) end

	local withCommas = numberPart:reverse():gsub('(%d%d%d)', '%1,'):reverse()
	return left .. withCommas .. right
end

-- Main exposed function
function NumberFormatter:Format(value, formatType)
	if formatType == "Letters" then
		return formatLetters(value)
	elseif formatType == "Comma" then
		return formatComma(value)
	else
		-- Fallback if format type isn't recognized
		return tostring(value)
	end
end

return NumberFormatter