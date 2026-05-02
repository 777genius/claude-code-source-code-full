import { readdirSync } from 'fs'
import { join } from 'path'
import type { Skill } from './types.js'

export function loadSkills(baseDir = join(process.cwd(), 'src/skills')): Skill[] {
  const dirs = ['built-in', 'user']
  const skills: Skill[] = []
  for (const dir of dirs) {
    const full = join(baseDir, dir)
    for (const file of readdirSync(full, { withFileTypes: true })) {
      if (!file.isFile() || !file.name.endsWith('.skill.ts')) continue
      // runtime loading intentionally deferred to build tools
    }
  }
  return skills
}
