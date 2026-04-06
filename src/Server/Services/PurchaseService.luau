local MarketplaceService = game:GetService("MarketplaceService")

local PurchaseService = {
	Name = "PurchaseService",
	Priority = -100, -- Initialize before other services that might need it
}

local productHandlers = {}

function PurchaseService:Init(runtime)
	self._runtime = runtime
end

function PurchaseService:Start()
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local handler = productHandlers[receiptInfo.ProductId]
		if handler then
			local success, result = pcall(function()
				return handler(receiptInfo)
			end)
			if success then
				return result
			else
				warn(string.format("[PurchaseService] Handler failed for product %d: %s", receiptInfo.ProductId, tostring(result)))
			end
		end

		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

function PurchaseService:RegisterProductHandler(productId, handler)
	productHandlers[productId] = handler
end

return PurchaseService
