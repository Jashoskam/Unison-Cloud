import { Router, Request, Response, NextFunction } from "express";
import { CodeIndexer } from "../indexer/CodeIndexer";
import { AppError } from "../middleware/errorHandler";

export const searchRouter = Router();

searchRouter.post("/index", async (req: Request, res: Response, next: NextFunction) => {
    try {
        const { dir } = req.body;
        const targetDir = typeof dir === "string" ? dir : process.cwd();
        const stats = await CodeIndexer.getInstance().indexWorkspace(targetDir);
        res.json({
            success: true,
            indexedFiles: stats.indexedFiles,
            totalSymbols: stats.totalSymbols
        });
    } catch (err: any) {
        next(new AppError(`Indexing failed: ${err.message}`, 500, true, "INDEXING_ERROR"));
    }
});

searchRouter.get("/search", (req: Request, res: Response, next: NextFunction) => {
    try {
        const searchQuery: string = typeof req.query.q === "string" ? req.query.q : "";
        const limitStr: string = typeof req.query.limit === "string" ? req.query.limit : "15";
        const limit = parseInt(limitStr, 10);

        if (!searchQuery) {
            return res.json({ success: true, query: "", results: [] });
        }

        const results = CodeIndexer.getInstance().searchCodebase(searchQuery, limit);
        res.json({
            success: true,
            query: searchQuery,
            totalMatches: results.length,
            results
        });
    } catch (err: any) {
        next(new AppError(`Search failed: ${err.message}`, 500, true, "SEARCH_ERROR"));
    }
});
