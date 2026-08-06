import { Request, Response, NextFunction } from "express";

export class AppError extends Error {
    public readonly statusCode: number;
    public readonly isOperational: boolean;
    public readonly errorCode?: string;

    constructor(message: string, statusCode: number, isOperational = true, errorCode?: string) {
        super(message);
        Object.setPrototypeOf(this, new.target.prototype);
        this.statusCode = statusCode;
        this.isOperational = isOperational;
        this.errorCode = errorCode;
        Error.captureStackTrace(this, this.constructor);
    }
}

export function errorHandler(err: any, req: Request, res: Response, _next: NextFunction) {
    const statusCode = err.statusCode || 500;
    const isOperational = err.isOperational !== undefined ? err.isOperational : false;
    const errorCode = err.errorCode || "INTERNAL_SERVER_ERROR";

    console.error(`[Render API Error] [${req.method} ${req.path}] error:`, err);

    const isProd = process.env.NODE_ENV === "production";
    const response: any = {
        error: {
            message: isOperational || !isProd ? err.message : "An internal server error occurred.",
            errorCode,
            statusCode,
            traceId: (req as any).traceId
        }
    };

    if (!isProd) {
        response.error.stack = err.stack;
    }

    res.status(statusCode).json(response);
}

export function validateRequestBody(requiredFields: string[]) {
    return (req: Request, _res: Response, next: NextFunction) => {
        if (!req.body || typeof req.body !== "object") {
            return next(new AppError("Invalid or missing request JSON body", 400, true, "INVALID_BODY"));
        }
        for (const field of requiredFields) {
            if (req.body[field] === undefined || req.body[field] === null) {
                return next(new AppError(`Missing required field: '${field}'`, 400, true, "MISSING_FIELD"));
            }
        }
        next();
    };
}
