import { z } from 'zod/v4'
import type { VideoSkill } from '../index.js'

export const LowerThirdSkill: VideoSkill = {
  name: 'lower-third',
  description: 'Lower third overlay',
  version: '1.0.0',
  inputs: z.object({ compositionId: z.string().default('lower-third') }),
  /** Execute the lower-third skill and return generated composition code. */
  async execute(inputs) {
    const parsed = this.inputs.parse(inputs)
    return { code: `// lower-third skill for ${parsed.compositionId}`, compositionId: parsed.compositionId }
  },
}
