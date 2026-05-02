import type { Scene } from './types.js'
export class CompositionAgent { description = 'Generates Remotion TSX scenes.'; /** Run composition generation for a scene. */ async run(scene: Scene) { return { sceneId: scene.id, file: `${scene.id}.tsx` } } }
