import type { VideoPlugin } from '../index.js'

export const AspectRatioPlugin: VideoPlugin = {
  name: 'aspect-ratio',
  description: 'aspect-ratio plugin for Red Cross Remo CLI',
  version: '1.0.0',
  enabled: true,
  hooks: {
    /** Run aspect-ratio startup checks. */
    onStartup: async () => {},
    /** Run aspect-ratio before render hook. */
    beforeRender: async () => {},
    /** Run aspect-ratio after render hook. */
    afterRender: async () => {},
    /** Run aspect-ratio error hook. */
    onError: async (_error: Error) => {},
  },
}
