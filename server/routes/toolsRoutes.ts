import { Router, Request, Response, NextFunction } from "express";
import { PluginRegistry } from "../plugins/PluginRegistry";
import { AppError } from "../middleware/errorHandler";
import { agentToolCallLogger } from "../middleware/logger";

export const toolsRouter = Router();

toolsRouter.get("/registry", (_req: Request, res: Response) => {
    const plugins = PluginRegistry.getRegisteredPlugins();
    const schemas = PluginRegistry.getAllToolsSchema();
    const metrics = PluginRegistry.getMetrics();
    res.json({
        success: true,
        pluginsCount: plugins.length,
        toolsCount: schemas.length,
        metrics,
        plugins: plugins.map(p => ({
            name: p.name,
            version: p.version,
            description: p.description,
            tools: p.tools.map(t => t.name)
        })),
        schemas
    });
});

toolsRouter.get("/metrics", (_req: Request, res: Response) => {
    res.json({
        success: true,
        timestamp: new Date().toISOString(),
        memoryUsage: process.memoryUsage(),
        uptime: Math.floor(process.uptime()),
        metrics: PluginRegistry.getMetrics()
    });
});

toolsRouter.post("/execute", async (req: Request, res: Response, next: NextFunction) => {
    try {
        const { toolName, args } = req.body;
        if (!toolName || typeof toolName !== "string") {
            return next(new AppError("Parameter 'toolName' (string) is required", 400, true, "INVALID_TOOL_NAME"));
        }

        const toolArgs = args || {};
        const traceId = (req as any).traceId;
        agentToolCallLogger(toolName, toolArgs, traceId);

        const result = await PluginRegistry.executeTool(toolName, toolArgs, { req, traceId });
        res.json({
            success: true,
            toolName,
            traceId,
            result
        });
    } catch (err: any) {
        next(new AppError(err.message || "Tool execution failed", 500, true, "TOOL_EXECUTION_ERROR"));
    }
});
