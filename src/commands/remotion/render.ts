import type { Command } from '../../types/command.js'
export default { type:'local-jsx', name:'render', description:'Render a Remotion video', userFacingName:()=>'/render', isEnabled:()=>true, async call(){ return null } } satisfies Command
