import { z } from 'zod/v4'
import type { VideoSkill } from '../index.js'

export const SlideshowSkill: VideoSkill = {
  name: 'slideshow',
  description: 'Ken Burns slideshow',
  version: '1.0.0',
  inputs: z.object({ compositionId: z.string().default('slideshow') }),
  /** Execute the slideshow skill and return generated composition code. */
  async execute(inputs) {
    const parsed = this.inputs.parse(inputs)
    return { code: `// slideshow skill for ${parsed.compositionId}`, compositionId: parsed.compositionId }
  },
}
