export type FunnelSessions = { [number]: string }
export type CustomFieldNames = "CustomField01" | "CustomField02" | "CustomField03"
export type CustomFields = { [CustomFieldNames]: string }
export type SteppedMethodNames = "FunnelStep" | "OnboardingFunnelStep"
export type AnalyticsMethodNames = "CustomEvent" | "EconomyEvent" | SteppedMethodNames

export type Actions = {
	action: () -> (),
	resolve: (() -> ())?,
	reject: ((string) -> ())?,
	stepNumber: number?,
}

export type Queue = {
	[Player]: {
		[AnalyticsMethodNames]: { Actions },
	},
}

return {}
