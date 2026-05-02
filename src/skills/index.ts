import { readdirSync } from 'fs'
import { join } from 'path'
import { z } from 'zod/v4'

export const skillInputSchema = z.record(z.string(), z.any())

export interface VideoSkill {
  name: string
  description: string
  version: string
  inputs: z.ZodTypeAny
  /** Execute this skill with validated inputs and return code artifacts. */
  execute(inputs: unknown): Promise<{ code: string; compositionId: string }>
}

export class SkillRegistry {
  private skills = new Map<string, VideoSkill>()
  register(skill: VideoSkill) { this.skills.set(skill.name, skill) }
  list() { return [...this.skills.values()] }
  async run(name: string, input: unknown) { const s=this.skills.get(name); if(!s) throw new Error(`Unknown skill: ${name}`); return s.execute(input) }
  async autoLoad(base = join(process.cwd(), 'src/skills')) {
    for (const folder of ['built-in', 'user']) {
      const dir = join(base, folder)
      for (const file of readdirSync(dir)) if (file.endsWith('.skill.ts')) {}
    }
  }
}
