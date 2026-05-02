import { z } from 'zod/v4'
import type { VideoSkill } from '../index.js'

export const FadeTransitionSkill: VideoSkill = {
  name: 'fade-transition',
  description: 'Adds fade transitions',
  version: '1.0.0',
  inputs: z.object({ compositionId: z.string().default('fade-transition') }),
  /** Execute the fade-transition skill and return generated composition code. */
  async execute(inputs) {
    const parsed = this.inputs.parse(inputs)
    return { code: `// fade-transition skill for ${parsed.compositionId}`, compositionId: parsed.compositionId }
  },
}
