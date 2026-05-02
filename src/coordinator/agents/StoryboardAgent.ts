import type { Scene } from './types.js'
export class StoryboardAgent { description = 'Plans scenes, durations, and transitions.'; /** Run storyboard planning. */ async run(request: string): Promise<Scene[]> { return [{ id: 'scene-1', prompt: request, durationSeconds: 5 }] } }
