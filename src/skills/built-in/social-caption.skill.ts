import { z } from 'zod/v4'
import type { VideoSkill } from '../index.js'

export const SocialCaptionSkill: VideoSkill = {
  name: 'social-caption',
  description: 'Short-form social captions',
  version: '1.0.0',
  inputs: z.object({ compositionId: z.string().default('social-caption') }),
  /** Execute the social-caption skill and return generated composition code. */
  async execute(inputs) {
    const parsed = this.inputs.parse(inputs)
    return { code: `// social-caption skill for ${parsed.compositionId}`, compositionId: parsed.compositionId }
  },
}
