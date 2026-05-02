import type { VideoPlugin } from '../index.js'

export const AutoCaptionsPlugin: VideoPlugin = {
  name: 'auto-captions',
  description: 'auto-captions plugin for Red Cross Remo CLI',
  version: '1.0.0',
  enabled: true,
  hooks: {
    /** Run auto-captions startup checks. */
    onStartup: async () => {},
    /** Run auto-captions before render hook. */
    beforeRender: async () => {},
    /** Run auto-captions after render hook. */
    afterRender: async () => {},
    /** Run auto-captions error hook. */
    onError: async (_error: Error) => {},
  },
}
