import React from 'react'
import { Box, Text } from 'ink'
import type { AgentStatus } from './agents/types.js'

export function AgentStatusUI({ statuses }: { statuses: AgentStatus[] }) {
  return <Box flexDirection='column' borderStyle='round' borderColor='red'><Text color='red'>✚ Red Cross Remo — Agent Activity</Text>{statuses.map(s => <Text key={s.name}>{s.emoji} {s.name}: {s.task}</Text>)}</Box>
}
