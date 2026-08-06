import { Router, Request, Response, NextFunction } from "express";
import { AppError } from "../middleware/errorHandler";

export const authRouter = Router();

// BYOK Key Store for AI providers
let unisonAiKeysStore = {
    geminiKey: process.env.GEMINI_API_KEY || "",
    claudeKey: process.env.CLAUDE_API_KEY || process.env.ANTHROPIC_API_KEY || "",
    chatgptKey: process.env.OPENAI_API_KEY || "",
    lastUpdated: new Date().toISOString()
};

authRouter.get("/keys", (_req: Request, res: Response) => {
    res.json({
        success: true,
        store: {
            hasGeminiKey: !!unisonAiKeysStore.geminiKey,
            hasClaudeKey: !!unisonAiKeysStore.claudeKey,
            hasChatGPTKey: !!unisonAiKeysStore.chatgptKey,
            lastUpdated: unisonAiKeysStore.lastUpdated
        }
    });
});

authRouter.post("/keys", (req: Request, res: Response, next: NextFunction) => {
    try {
        const { geminiKey, claudeKey, chatgptKey } = req.body;
        if (geminiKey !== undefined) unisonAiKeysStore.geminiKey = geminiKey;
        if (claudeKey !== undefined) unisonAiKeysStore.claudeKey = claudeKey;
        if (chatgptKey !== undefined) unisonAiKeysStore.chatgptKey = chatgptKey;
        unisonAiKeysStore.lastUpdated = new Date().toISOString();

        res.json({
            success: true,
            message: "AI provider API key vault updated successfully.",
            store: {
                hasGeminiKey: !!unisonAiKeysStore.geminiKey,
                hasClaudeKey: !!unisonAiKeysStore.claudeKey,
                hasChatGPTKey: !!unisonAiKeysStore.chatgptKey,
                lastUpdated: unisonAiKeysStore.lastUpdated
            }
        });
    } catch (e) {
        next(new AppError("Failed to update AI keys store", 500, true, "AUTH_KEY_UPDATE_ERROR"));
    }
});

authRouter.post("/session/verify", (req: Request, res: Response) => {
    const token = req.headers.authorization;
    if (!token) {
        res.status(401).json({ success: false, error: "Missing Authorization header token" });
        return;
    }
    res.json({
        success: true,
        status: "AUTHENTICATED",
        user: { id: "user_render_active", role: "admin" }
    });
});
