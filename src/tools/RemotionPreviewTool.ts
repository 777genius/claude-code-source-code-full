import { execa } from 'execa'
import { z } from 'zod/v4'
export const RemotionPreviewInput = z.object({ projectRoot:z.string().default(process.cwd()), compositionId:z.string().optional(), port:z.number().default(3000) })
export class RemotionPreviewTool { description='Launch Remotion Studio preview'; /** Execute preview command and return running process. */ async execute(input: unknown){ const p=RemotionPreviewInput.parse(input); return execa('npx',['remotion','preview',p.projectRoot,'--port',String(p.port)]) } }
