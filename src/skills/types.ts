export interface SkillContext { input: string }
export interface Skill { name: string; description: string; execute(context: SkillContext): Promise<string> }
