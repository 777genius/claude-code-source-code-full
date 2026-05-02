import type { Command } from '../../types/command.js'
export default { type:'local-jsx', name:'storyboard', description:'Run storyboard coordinator workflow', userFacingName:()=>'/storyboard', isEnabled:()=>true, async call(){ return null } } satisfies Command
