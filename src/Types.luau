export type CustomFieldNames = "CustomField01" | "CustomField02" | "CustomField03"
export type CustomFields = { [CustomFieldNames]: string }
export type SteppedEvents = "FunnelStep" | "OnboardingFunnelStep"
export type AnalyticsEvents = "CustomEvent" | "EconomyEvent" | SteppedEvents

export type Actions = {
	callBack: () -> (),
	resolve: () -> (),
	reject: (string?) -> (),
}

export type MetaData = {
	stepNumber: number,
	funnelSessionId: string?,
}

export type QueueObject = {
	player: Player,
	eventType: string,
	actions: Actions,
	metaData: MetaData?,
}

export type Queue = {
	Enqueue: (self: Queue, value: QueueObject) -> (),
	Dequeue: (self: Queue) -> QueueObject?,
	Peek: (self: Queue) -> QueueObject?,
	IsEmpty: (self: Queue) -> boolean,
	Size: (self: Queue) -> number,
	Clear: (self: Queue) -> (),
	Remove: (self: Queue, value: QueueObject) -> boolean,
	Items: { QueueObject }, -- Table to store the dictionaries
}

return {}
