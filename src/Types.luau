export type CustomFieldNames = "CustomField01" | "CustomField02" | "CustomField03"
export type CustomFields = { [CustomFieldNames]: string }
export type SteppedMethodNames = "FunnelStep" | "OnboardingFunnelStep"
export type AnalyticsMethodNames = "CustomEvent" | "EconomyEvent" | SteppedMethodNames

export type Actions = {
	callBack: () -> (),
	resolve: () -> (),
	reject: (string?) -> (),
}

export type MetaData = {
	stepNumber: number,
	funnelSessionId: string?,
}

export type QueueData = { actions: Actions, metaData: MetaData? }

export type Queue = {
	[Player]: {
		[AnalyticsMethodNames]: { QueueData },
	},
}

return {}
