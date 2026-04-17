export type CustomFieldNames = "CustomField01" | "CustomField02" | "CustomField03"
export type CustomFields = { [CustomFieldNames]: string }
export type EconomyTransactionType = Enum.AnalyticsEconomyTransactionType | { Name: string }

export type SteppedMetaData = {
	stepNumber: number,
	funnelName: string?,
	funnelSessionId: string?,
}

export type QueueObject = {
	player: Player,
	eventType: string,
	callBack: () -> (),
	metaData: SteppedMetaData?,
}

export type EconomyData = {
	player: Player,
	flowType: Enum.AnalyticsEconomyFlowType,
	currencyType: string,
	amount: number,
	endingBalance: number,
	transactionType: EconomyTransactionType,
	itemSKU: string?,
	customFields: CustomFields?,
}

return {}
