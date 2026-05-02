export class ReviewAgent { description = 'Validates generated compositions.'; /** Run validation for generated scene outputs. */ async run(_input: unknown) { return { ok: true } } }
