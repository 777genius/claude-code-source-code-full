export interface PluginHooksContext { outputPath?: string; error?: Error }
export interface Plugin {
  name: string
  enabled: boolean
  /** onStartup lifecycle hook. */
  onStartup?(): Promise<void>
  /** beforeRender lifecycle hook. */
  beforeRender?(ctx: PluginHooksContext): Promise<void>
  /** afterRender lifecycle hook. */
  afterRender?(ctx: PluginHooksContext): Promise<void>
  /** onError lifecycle hook. */
  onError?(ctx: PluginHooksContext): Promise<void>
}
