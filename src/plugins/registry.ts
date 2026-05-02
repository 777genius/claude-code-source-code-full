import type { Plugin } from './types.js'

export class PluginRegistry {
  private readonly plugins = new Map<string, Plugin>()
  register(plugin: Plugin) { this.plugins.set(plugin.name, plugin) }
  list() { return [...this.plugins.values()] }
  enable(name: string) { const p = this.plugins.get(name); if (p) p.enabled = true }
  disable(name: string) { const p = this.plugins.get(name); if (p) p.enabled = false }
}
