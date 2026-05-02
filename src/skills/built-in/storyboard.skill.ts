import type { Skill, SkillContext } from '../types.js'

export default {
  name: 'storyboard-json',
  description: 'Converts plain-English concepts into scene JSON',
  /** Execute storyboard generation skill. */
  async execute(context: SkillContext): Promise<string> {
    return JSON.stringify({ prompt: context.input, scenes: [] }, null, 2)
  },
} satisfies Skill
