import type { VideoPlugin } from '../index.js'

export const FfmpegCheckPlugin: VideoPlugin = {
  name: 'ffmpeg-check',
  description: 'ffmpeg-check plugin for Red Cross Remo CLI',
  version: '1.0.0',
  enabled: true,
  hooks: {
    /** Run ffmpeg-check startup checks. */
    onStartup: async () => {},
    /** Run ffmpeg-check before render hook. */
    beforeRender: async () => {},
    /** Run ffmpeg-check after render hook. */
    afterRender: async () => {},
    /** Run ffmpeg-check error hook. */
    onError: async (_error: Error) => {},
  },
}
