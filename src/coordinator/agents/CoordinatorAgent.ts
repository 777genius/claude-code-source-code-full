import { AssetAgent } from './AssetAgent.js'
import { CompositionAgent } from './CompositionAgent.js'
import { RenderAgent } from './RenderAgent.js'
import { ReviewAgent } from './ReviewAgent.js'
import { StoryboardAgent } from './StoryboardAgent.js'

export class CoordinatorAgent {
  description = 'Coordinates storyboard, assets, composition, review, and render agents.'
  /** Run the full multi-agent video workflow. */
  async run(prompt: string) {
    const storyboard = await new StoryboardAgent().run(prompt)
    const pairs = await Promise.all(storyboard.map(async scene => ({ assets: await new AssetAgent().run(scene), composition: await new CompositionAgent().run(scene) })))
    await new ReviewAgent().run(pairs)
    return new RenderAgent().run(pairs)
  }
}
