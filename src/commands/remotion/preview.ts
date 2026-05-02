import type { Command } from '../../types/command.js'
export default { type:'local-jsx', name:'preview', description:'Preview Remotion Studio', userFacingName:()=>'/preview', isEnabled:()=>true, async call(){ return null } } satisfies Command
