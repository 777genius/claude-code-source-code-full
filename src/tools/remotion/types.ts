import { z } from 'zod/v4'

export const renderInput = z.object({ compositionId: z.string(), outputPath: z.string(), fps: z.number().optional(), width: z.number().optional(), height: z.number().optional(), startFrame: z.number().optional(), endFrame: z.number().optional(), codec: z.string().optional() })
export const previewInput = z.object({ projectRoot: z.string(), compositionId: z.string(), port: z.number().optional() })
export const compositionInput = z.object({ name: z.string(), prompt: z.string(), durationInSeconds: z.number().optional(), fps: z.number().optional(), width: z.number().optional(), height: z.number().optional(), outputDir: z.string().optional() })
export const assetInput = z.object({ action: z.enum(['download','list','validate','font']), url: z.string().optional(), filename: z.string().optional(), fontName: z.string().optional() })
export const pexelsInput = z.object({ type: z.enum(['photo','video']), query: z.string(), count: z.number().default(5), orientation: z.string().optional(), download: z.boolean().default(false), quality: z.string().optional() })
