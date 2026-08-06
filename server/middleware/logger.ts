import { Request, Response, NextFunction } from "express";

export interface LoggedRequest extends Request {
    traceId?: string;
    startTime?: number;
    path: string;
    method: string;
    ip: string;
}

export function requestLogger(req: LoggedRequest, res: Response, next: NextFunction) {
    // Only log API routes to prevent clogging logs with frontend static assets/Vite module requests
    if (!req.path.startsWith("/api")) {
        return next();
    }

    const traceId = `trc_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    req.traceId = traceId;
    req.startTime = Date.now();

    res.setHeader("X-Trace-ID", traceId);

    const logPrefix = `[Render API] [${traceId}] [${req.method} ${req.path}]`;
    console.log(`${logPrefix} Incoming request from ${req.ip || "unknown"}`);

    res.on("finish", () => {
        const duration = req.startTime ? Date.now() - req.startTime : 0;
        const status = res.statusCode;
        const logMsg = `${logPrefix} Completed with status ${status} in ${duration}ms`;
        if (status >= 400) {
            console.warn(logMsg);
        } else {
            console.log(logMsg);
        }
    });

    next();
}

export function agentToolCallLogger(toolName: string, args: Record<string, any>, traceId?: string) {
    const tid = traceId || `trc_${Date.now()}`;
    console.log(`\x1b[36m[Agent Tool Exec] [${tid}] Tool: '${toolName}' | Args: ${JSON.stringify(args).slice(0, 150)}\x1b[0m`);
}
