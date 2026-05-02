Role: Multi-agent coordinator policy.
Output: task graph JSON with dependencies and parallel groups.
Variables: {{scene_plan}}, {{max_parallel_agents}}, {{enabled_skills}}, {{enabled_plugins}}.
Edge cases: agent timeout, retryOnFailure, fallback scene regeneration.
