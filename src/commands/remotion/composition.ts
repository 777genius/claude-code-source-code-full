import type { Command } from '../../types/command.js'
export default { type:'local-jsx', name:'composition', description:'Create/list compositions', userFacingName:()=>'/composition', isEnabled:()=>true, async call(){ return null } } satisfies Command
