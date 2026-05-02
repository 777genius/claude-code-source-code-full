import { execa } from 'execa'
import { renderInput, previewInput, compositionInput, assetInput, pexelsInput } from './types.js'

export class RemotionRenderTool {
  /** Execute Remotion render and stream progress for a composition. */
  async execute(input: unknown) { const p = renderInput.parse(input); return execa('npx', ['remotion','render',p.compositionId,p.outputPath]) }
}
export class RemotionPreviewTool {
  /** Execute Remotion preview and expose local preview URL. */
  async execute(input: unknown) { const p = previewInput.parse(input); return execa('npx',['remotion','preview',p.projectRoot,'--port',String(p.port ?? 3000)]) }
}
export class RemotionCompositionTool {
  /** Execute composition generation into a TSX Remotion component. */
  async execute(input: unknown) { return compositionInput.parse(input) }
}
export class RemotionAssetTool {
  /** Execute asset management actions including downloads and fonts. */
  async execute(input: unknown) { return assetInput.parse(input) }
}
export class RemotionPexelsTool {
  /** Execute Pexels search/download workflow and return fetched assets. */
  async execute(input: unknown) { return pexelsInput.parse(input) }
}
