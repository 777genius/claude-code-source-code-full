import type { Plugin } from '../types.js'

const creditsPlugin: Plugin = {
  name: 'credits-tracker',
  enabled: true,
  async onStartup() {},
  async beforeRender() {},
  async afterRender() {},
  async onError() {},
}

export default creditsPlugin
