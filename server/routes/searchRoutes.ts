import { Router, Request, Response, NextFunction } from "express";
import { CodeIndexer } from "../indexer/CodeIndexer";
import { AppError } from "../middleware/errorHandler";

export const searchRouter = Router();

searchRouter.post("/index", async (req: Request, res: Response, next: NextFunction) => {
    try {
        const { dir } = req.body;
        const targetDir = dir || process.cwd();
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
        const query = (req.query.q as String) || "";
        const limit = parseInt((req.query.limit as string) || "15", 10);

        if (!query) {
            return res.json({ success: true, query: "", results: [] });
        }

        const results = CodeIndexer.getInstance().searchCodebase(query, limit);
        res.json({
            success: true,
            query,
            totalMatches: results.length,
            results
        });
    } catch (err: any) {
        next(new AppError(`Search failed: ${err.message}`, 500, true, "SEARCH_ERROR"));
    }
});
