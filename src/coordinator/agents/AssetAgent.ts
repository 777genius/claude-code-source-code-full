import type { Scene } from './types.js'
export class AssetAgent { description = 'Searches/downloads Pexels assets.'; /** Run asset search for a scene. */ async run(scene: Scene) { return { sceneId: scene.id, assets: [] as string[] } } }
