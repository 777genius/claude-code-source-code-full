import type { Command } from '../../types/command.js'
export default { type:'local-jsx', name:'video-export', description:'Export video with preset', userFacingName:()=>'/export', isEnabled:()=>true, async call(){ return null } } satisfies Command
