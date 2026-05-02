import { z } from 'zod/v4'

export const mcpToolSchema = z.object({ name: z.string(), description: z.string(), endpoint: z.string().url() })
export type McpTool = z.infer<typeof mcpToolSchema>

export const builtInMcpTools: McpTool[] = [
  { name: 'stock-footage-search', description: 'Search stock media providers', endpoint: 'https://mcp.video.local/stock' },
  { name: 'audio-library', description: 'Discover royalty free music and fx', endpoint: 'https://mcp.video.local/audio' },
  { name: 'caption-generator', description: 'Generate subtitles and captions', endpoint: 'https://mcp.video.local/captions' },
]
