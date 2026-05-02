import type { VideoPlugin } from '../index.js'

export const RemotionPlayerPlugin: VideoPlugin = {
  name: 'remotion-player',
  description: 'remotion-player plugin for Red Cross Remo CLI',
  version: '1.0.0',
  enabled: true,
  hooks: {
    /** Run remotion-player startup checks. */
    onStartup: async () => {},
    /** Run remotion-player before render hook. */
    beforeRender: async () => {},
    /** Run remotion-player after render hook. */
    afterRender: async () => {},
    /** Run remotion-player error hook. */
    onError: async (_error: Error) => {},
  },
}
