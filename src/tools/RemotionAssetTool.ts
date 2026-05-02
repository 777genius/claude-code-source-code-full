import { z } from 'zod/v4'
export const RemotionAssetInput = z.object({ action:z.enum(['download','list','validate','font']), url:z.string().optional(), filename:z.string().optional(), fontName:z.string().optional() })
export class RemotionAssetTool { description='Manage Remotion assets and fonts'; /** Execute asset actions for download/list/validate/font workflows. */ async execute(input: unknown){ return RemotionAssetInput.parse(input) } }
