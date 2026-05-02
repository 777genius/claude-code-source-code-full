import type { VideoPlugin } from '../index.js'

export const ProjectInitPlugin: VideoPlugin = {
  name: 'project-init',
  description: 'project-init plugin for Red Cross Remo CLI',
  version: '1.0.0',
  enabled: true,
  hooks: {
    /** Run project-init startup checks. */
    onStartup: async () => {},
    /** Run project-init before render hook. */
    beforeRender: async () => {},
    /** Run project-init after render hook. */
    afterRender: async () => {},
    /** Run project-init error hook. */
    onError: async (_error: Error) => {},
  },
}
