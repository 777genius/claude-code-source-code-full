import { readdirSync } from 'fs'
import { join } from 'path'

export interface VideoPlugin {
  name: string
  description: string
  version: string
  enabled: boolean
  hooks: {
    /** Run at startup. */
    onStartup?: () => Promise<void>
    /** Run before render starts. */
    beforeRender?: () => Promise<void>
    /** Run after render finishes. */
    afterRender?: () => Promise<void>
    /** Run when lifecycle errors happen. */
    onError?: (error: Error) => Promise<void>
  }
}

export class PluginRegistry {
  private plugins = new Map<string, VideoPlugin>()
  register(plugin: VideoPlugin) { this.plugins.set(plugin.name, plugin) }
  list() { return [...this.plugins.values()] }
  enable(name: string) { const p=this.plugins.get(name); if(p) p.enabled=true }
  disable(name: string) { const p=this.plugins.get(name); if(p) p.enabled=false }
  async autoLoad(base = join(process.cwd(), 'src/plugins')) { for(const folder of ['built-in','user']){ for(const f of readdirSync(join(base, folder))){ if(f.endsWith('.plugin.ts')){} } } }
}
