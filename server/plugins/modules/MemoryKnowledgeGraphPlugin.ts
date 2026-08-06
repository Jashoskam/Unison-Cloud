import { PluginDefinition } from "../PluginRegistry";

interface MemoryNode {
    id: string;
    concept: string;
    category: string;
    tags: string[];
    details: string;
    createdAt: string;
    connections: string[];
}

const memoryStore: MemoryNode[] = [
    {
        id: "mem_001",
        concept: "Unison macOS Architecture",
        category: "System Design",
        tags: ["swiftui", "render", "express", "server"],
        details: "Unison pairs a native SwiftUI macOS app with an Express backend running on Render and Cloud Run.",
        createdAt: "2026-08-01T10:00:00Z",
        connections: ["mem_002"]
    },
    {
        id: "mem_002",
        concept: "Gemini 3.5 & Antigravity Intelligence",
        category: "AI Agent",
        tags: ["gemini", "antigravity", "tools", "plugins"],
        details: "Antigravity powers multi-turn agentic task loops with full PluginRegistry schema execution.",
        createdAt: "2026-08-05T14:30:00Z",
        connections: ["mem_001"]
    }
];

export const MemoryKnowledgeGraphPlugin: PluginDefinition = {
    name: "MemoryKnowledgeGraphPlugin",
    description: "Long-term Knowledge Graph Memory Engine for storing, indexing, and retrieving persistent context across sessions.",
    version: "2.0.0",
    tools: [
        {
            name: "memory_store_node",
            description: "Stores a new concept or user preference into the persistent long-term knowledge graph.",
            schema: {
                type: "object",
                properties: {
                    concept: { type: "string", description: "Name/heading of the concept" },
                    category: { type: "string", description: "Category e.g., 'User Preference', 'Project Architecture', 'Security Policy'" },
                    details: { type: "string", description: "Detailed summary text" },
                    tags: { type: "string", description: "Comma-separated list of tags" }
                },
                required: ["concept", "details"]
            },
            handler: async (args) => {
                const tagList = (args.tags || "").split(",").map((t: string) => t.trim()).filter(Boolean);
                const newNode: MemoryNode = {
                    id: `mem_${Date.now()}`,
                    concept: args.concept,
                    category: args.category || "General",
                    tags: tagList,
                    details: args.details,
                    createdAt: new Date().toISOString(),
                    connections: []
                };

                memoryStore.push(newNode);

                return {
                    status: "STORED",
                    nodeId: newNode.id,
                    totalNodesInMemory: memoryStore.length,
                    storedNode: newNode
                };
            }
        },
        {
            name: "memory_query_graph",
            description: "Queries the persistent knowledge graph for matching concepts, tags, or categories.",
            schema: {
                type: "object",
                properties: {
                    query: { type: "string", description: "Search query or keyword" },
                    category: { type: "string", description: "Optional category filter" }
                },
                required: ["query"]
            },
            handler: async (args) => {
                const q = (args.query || "").toLowerCase();
                const matched = memoryStore.filter(node => 
                    node.concept.toLowerCase().includes(q) ||
                    node.details.toLowerCase().includes(q) ||
                    node.tags.some(t => t.toLowerCase().includes(q))
                );

                return {
                    status: "SUCCESS",
                    query: args.query,
                    matchedCount: matched.length,
                    results: matched
                };
            }
        }
    ]
};
