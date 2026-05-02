import { readFileSync, writeFileSync } from 'fs'
import { join } from 'path'
import { z } from 'zod/v4'
export const RemotionCompositionInput = z.object({ name:z.string(), prompt:z.string(), durationInSeconds:z.number().default(10), fps:z.number().default(30), width:z.number().default(1920), height:z.number().default(1080), outputDir:z.string().default('./src/compositions') })
export class RemotionCompositionTool { description='Generate Remotion composition TSX files'; /** Execute composition generation using prompt template and persist TSX output. */ async execute(input: unknown){ const p=RemotionCompositionInput.parse(input); const tpl=readFileSync(join(process.cwd(),'prompts/composition-generator.md'),'utf8'); const content=`/* generated */\n// ${p.name}\n// prompt: ${p.prompt}\n`; const file=join(p.outputDir,`${p.name}.tsx`); writeFileSync(file, content); return { file, promptTemplate: tpl.slice(0,120) } } }
