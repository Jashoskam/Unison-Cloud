export interface ToolParameter {
    type: string;
    description: string;
    enum?: string[];
    default?: any;
    items?: any;
}

export interface ToolJSONSchema {
    type: "object";
    properties: Record<string, ToolParameter>;
    required?: string[];
}

export interface PluginDefinition {
    name: string;
    description: string;
    version: string;
    tools: {
        name: string;
        description: string;
        schema: ToolJSONSchema;
        handler: (args: Record<string, any>, context?: any) => Promise<any> | any;
    }[];
}

class PluginRegistryService {
    private plugins = new Map<string, PluginDefinition>();
    private toolToPluginMap = new Map<string, { pluginName: string; toolIndex: number }>();
    
    // Performance & Execution Metrics
    private metrics = {
        totalExecutions: 0,
        successfulExecutions: 0,
        failedExecutions: 0,
        avgExecutionTimeMs: 0,
        activeTasks: 0,
        maxConcurrency: 5
    };

    public registerPlugin(plugin: PluginDefinition): void {
        this.plugins.set(plugin.name, plugin);
        plugin.tools.forEach((tool, idx) => {
            if (this.toolToPluginMap.has(tool.name)) {
                console.warn(`[PluginRegistry] Tool name collision: '${tool.name}' is being overwritten by plugin '${plugin.name}'`);
            }
            this.toolToPluginMap.set(tool.name, { pluginName: plugin.name, toolIndex: idx });
        });
        console.log(`[PluginRegistry] Registered plugin '${plugin.name}' v${plugin.version} with ${plugin.tools.length} tools.`);
    }

    public getRegisteredPlugins(): PluginDefinition[] {
        return Array.from(this.plugins.values());
    }

    public getMetrics() {
        return {
            ...this.metrics,
            registeredPluginsCount: this.plugins.size,
            registeredToolsCount: this.toolToPluginMap.size
        };
    }

    public getAllToolsSchema(): Array<{ name: string; description: string; parameters: ToolJSONSchema }> {
        const schemas: Array<{ name: string; description: string; parameters: ToolJSONSchema }> = [];
        for (const plugin of this.plugins.values()) {
            for (const tool of plugin.tools) {
                schemas.push({
                    name: tool.name,
                    description: tool.description,
                    parameters: tool.schema
                });
            }
        }
        return schemas;
    }

    public async executeTool(toolName: string, args: Record<string, any>, context?: any): Promise<any> {
        const mapping = this.toolToPluginMap.get(toolName);
        if (!mapping) {
            throw new Error(`Tool '${toolName}' is not registered in the Plugin Registry.`);
        }

        const plugin = this.plugins.get(mapping.pluginName);
        if (!plugin) {
            throw new Error(`Plugin '${mapping.pluginName}' not found for tool '${toolName}'.`);
        }

        const tool = plugin.tools[mapping.toolIndex];
        
        // Basic schema validation for required fields
        if (tool.schema && tool.schema.required) {
            for (const reqField of tool.schema.required) {
                if (args[reqField] === undefined || args[reqField] === null) {
                    throw new Error(`Tool execution error: Missing required parameter '${reqField}' for tool '${toolName}'`);
                }
            }
        }

        // Throttle concurrency if active tasks exceed max limit to protect 512MB RAM on Render
        if (this.metrics.activeTasks >= this.metrics.maxConcurrency) {
            await new Promise(resolve => setTimeout(resolve, 50));
        }

        const startTime = performance.now();
        this.metrics.activeTasks++;
        this.metrics.totalExecutions++;

        console.log(`[PluginRegistry] Executing '${toolName}' via plugin '${plugin.name}' (Active: ${this.metrics.activeTasks})`);

        try {
            // Execution with 30s timeout guard to prevent worker hangs
            const timeoutPromise = new Promise((_, reject) => 
                setTimeout(() => reject(new Error(`Tool execution timeout: '${toolName}' exceeded 30000ms limit.`)), 30000)
            );

            const result = await Promise.race([
                Promise.resolve(tool.handler(args, context)),
                timeoutPromise
            ]);

            const duration = Math.round(performance.now() - startTime);
            this.metrics.successfulExecutions++;
            this.metrics.avgExecutionTimeMs = Math.round(
                ((this.metrics.avgExecutionTimeMs * (this.metrics.successfulExecutions - 1)) + duration) / this.metrics.successfulExecutions
            );

            return result;
        } catch (err: any) {
            this.metrics.failedExecutions++;
            console.error(`[PluginRegistry] Tool execution failed '${toolName}':`, err.message);
            throw err;
        } finally {
            this.metrics.activeTasks = Math.max(0, this.metrics.activeTasks - 1);
        }
    }
}

export const PluginRegistry = new PluginRegistryService();

