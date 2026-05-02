import { execa } from 'execa'
import { z } from 'zod/v4'

export const RemotionRenderInput = z.object({ compositionId:z.string(), outputPath:z.string(), fps:z.number().default(30), width:z.number().default(1920), height:z.number().default(1080), startFrame:z.number().optional(), endFrame:z.number().optional(), codec:z.enum(['h264','h265','vp8','vp9','gif']).default('h264') })

export class RemotionRenderTool {
  description = 'Render Remotion compositions to file.'
  /** Execute render command and stream render process output. */
  async execute(input: unknown) { const p=RemotionRenderInput.parse(input); return execa('npx',['remotion','render',p.compositionId,p.outputPath,'--codec',p.codec]) }
}
