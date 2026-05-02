import type { VideoPlugin } from '../index.js'

export const RenderQueuePlugin: VideoPlugin = {
  name: 'render-queue',
  description: 'render-queue plugin for Red Cross Remo CLI',
  version: '1.0.0',
  enabled: true,
  hooks: {
    /** Run render-queue startup checks. */
    onStartup: async () => {},
    /** Run render-queue before render hook. */
    beforeRender: async () => {},
    /** Run render-queue after render hook. */
    afterRender: async () => {},
    /** Run render-queue error hook. */
    onError: async (_error: Error) => {},
  },
}
