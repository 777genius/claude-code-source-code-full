import { z } from 'zod/v4'
import type { VideoSkill } from '../index.js'

export const DataChartSkill: VideoSkill = {
  name: 'data-chart',
  description: 'Animated chart from JSON',
  version: '1.0.0',
  inputs: z.object({ compositionId: z.string().default('data-chart') }),
  /** Execute the data-chart skill and return generated composition code. */
  async execute(inputs) {
    const parsed = this.inputs.parse(inputs)
    return { code: `// data-chart skill for ${parsed.compositionId}`, compositionId: parsed.compositionId }
  },
}
