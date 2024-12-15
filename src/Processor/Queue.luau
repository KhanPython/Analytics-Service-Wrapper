--!strict
local Types = require(script.Parent.Parent.Types)

local function CreateQueue(): Types.Queue
	local self = {
		Items = {} :: { Types.QueueObject },
	} :: Types.Queue

	function self:Enqueue(value: Types.QueueObject)
		table.insert(self.Items, value)
	end

	function self:Dequeue(): Types.QueueObject?
		if #self.Items == 0 then
			return nil
		end

		return table.remove(self.Items, 1)
	end

	function self:Peek(): Types.QueueObject?
		return self.Items[1]
	end

	function self:IsEmpty(): boolean
		return #self.Items == 0
	end

	function self:Size(): number
		return #self.Items
	end

	function self:Clear()
		self.Items = {}
	end

	-- Removes a specific element from the queue by reference
	function self:Remove(value: Types.QueueObject): boolean
		for i, v in pairs(self.Items) do
			if v == value then
				table.remove(self.Items, i)
				return true -- Successfully removed
			end
		end

		return false -- Element not found
	end

	return self
end

return CreateQueue()
