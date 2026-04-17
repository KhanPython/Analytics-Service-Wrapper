local Types = require(script.Parent.Parent.Types)

local serializeCustomFields = require(script.Parent.serializeCustomFields)

return function(
	transactionType: Types.EconomyTransactionType,
	itemSKU: string?,
	customFields: Types.CustomFields?
): string
	-- Discriminate Enum vs. { Name = string } so matching `.Name`s across the two
	-- forms don't collapse into the same bucket (and pick up a mismatched tx type).
	local kind = (typeof(transactionType) == "EnumItem") and "E" or "C"
	return `{kind}:{transactionType.Name}|{itemSKU or ""}|{serializeCustomFields(customFields)}`
end
