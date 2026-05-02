import type { VideoPlugin } from '../index.js'

export const ColorPalettePlugin: VideoPlugin = {
  name: 'color-palette',
  description: 'color-palette plugin for Red Cross Remo CLI',
  version: '1.0.0',
  enabled: true,
  hooks: {
    /** Run color-palette startup checks. */
    onStartup: async () => {},
    /** Run color-palette before render hook. */
    beforeRender: async () => {},
    /** Run color-palette after render hook. */
    afterRender: async () => {},
    /** Run color-palette error hook. */
    onError: async (_error: Error) => {},
  },
}
