local Types = require(script.Parent.Parent.Types)

return function(cf: Types.CustomFields?): string
	if cf == nil then
		return ""
	end
	local keys = {}
	for k in pairs(cf) do
		table.insert(keys, k)
	end
	table.sort(keys)
	local parts = table.create(#keys)
	for _, k in ipairs(keys) do
		parts[#parts + 1] = `{tostring(k)}={tostring(cf[k])}`
	end
	return table.concat(parts, ";")
end
