import { Router, Request, Response, NextFunction } from "express";
import { GoogleGenAI } from "@google/genai";
import { AppError } from "../middleware/errorHandler";

export const streamingRouter = Router();

const getGenAIClient = () => {
    return new GoogleGenAI({
        apiKey: process.env.GEMINI_API_KEY || "",
        httpOptions: {
            headers: {
                'User-Agent': 'aistudio-build'
            }
        }
    });
};

streamingRouter.post("/chat", async (req: Request, res: Response, next: NextFunction) => {
    try {
        const { message, modelName, prompt, history } = req.body;
        const textPrompt = prompt || message;

        if (!textPrompt) {
            return next(new AppError("Field 'message' or 'prompt' is required", 400, true, "MISSING_PROMPT"));
        }

        res.setHeader("Content-Type", "text/event-stream");
        res.setHeader("Cache-Control", "no-cache, no-transform");
        res.setHeader("Connection", "keep-alive");
        res.setHeader("X-Accel-Buffering", "no");
        if (typeof (res as any).flushHeaders === "function") {
            (res as any).flushHeaders();
        }

        const modelsToCascade = [
            modelName || "gemini-2.5-flash",
            "gemini-2.5-flash",
            "gemini-1.5-flash",
            "gemini-1.5-pro"
        ];
        const uniqueModels = Array.from(new Set(modelsToCascade));

        const systemInstruction = `You are Unison OS, an advanced AI-native desktop operating system and coding workspace. You are a world-class software engineer, systems architect, and technical writer.

CORE BEHAVIORAL RULES:
1. ELEGANT & NATURAL VOICE: Speak naturally, warmly, and eloquently. Avoid formulaic robotic phrasing or repetitive fluff.
2. THOROUGHNESS & PRECISION: Provide complete, production-quality responses. NEVER abbreviate, truncate, or use placeholders like '// ... rest of code ...' or '// TODO'. Every code file must be 100% complete.
3. TOOL USE: Base your reasoning and answers on actual workspace tools and files inspected.
4. FILE CREATION: When generating code files, specify the filename in the code fence header: \`\`\`language filename.ext.
5. RICH MARKDOWN: Use clean markdown headers (###), bold text, inline code, and language-tagged code blocks.
6. At the absolute end of your response, provide 3 relevant follow-up questions using: [FOLLOW_UPS: ["Q1", "Q2", "Q3"]].`;

        const googleGenAI = getGenAIClient();
        let streamSuccess = false;

        for (const targetModel of uniqueModels) {
            try {
                console.log(`[Streaming Route] Attempting model pathway: '${targetModel}'`);
                const responseStream = await googleGenAI.models.generateContentStream({
                    model: targetModel,
                    contents: textPrompt,
                    config: {
                        systemInstruction,
                        temperature: 0.7,
                        maxOutputTokens: 32768,
                        ...(targetModel.includes("2.5") ? { thinkingConfig: { thinkingBudget: 8192 } } : {})
                    }
                });

                for await (const chunk of responseStream) {
                    if (chunk.text) {
                        res.write(`data: ${JSON.stringify({ text: chunk.text, model: targetModel })}\n\n`);
                        if (typeof (res as any).flush === 'function') {
                            (res as any).flush();
                        }
                    }
                }
                streamSuccess = true;
                break;
            } catch (modelErr: any) {
                console.warn(`[Streaming Route] Model '${targetModel}' failed: ${modelErr.message}. Attempting fallback...`);
            }
        }

        if (!streamSuccess) {
            res.write(`data: ${JSON.stringify({ error: "All neural model pathways exhausted. Please check network connection or API Key." })}\n\n`);
        }

        res.write(`data: [DONE]\n\n`);
        res.end();
    } catch (err: any) {
        if (!res.headersSent) {
            next(new AppError(`Streaming failure: ${err.message}`, 500, true, "STREAMING_ERROR"));
        } else {
            res.write(`data: ${JSON.stringify({ error: err.message })}\n\n`);
            res.end();
        }
    }
});

streamingRouter.post("/live", async (req: Request, res: Response, next: NextFunction) => {
    try {
        const { prompt, voiceContext } = req.body;
        const textPrompt = prompt || "Hello Gemini Live";

        res.setHeader("Content-Type", "text/event-stream");
        res.setHeader("Cache-Control", "no-cache, no-transform");
        res.setHeader("Connection", "keep-alive");
        res.setHeader("X-Accel-Buffering", "no");

        const targetModel = "gemini-2.5-flash";
        const systemInstruction = `You are Gemini Live, the real-time AI voice assistant for Unison OS. Provide concise, direct, natural voice answers suitable for real-time speech synthesis. Keep answers under 3 sentences unless complex technical details are explicitly requested.`;

        const googleGenAI = getGenAIClient();
        const responseStream = await googleGenAI.models.generateContentStream({
            model: targetModel,
            contents: textPrompt,
            config: {
                systemInstruction,
                temperature: 0.7,
                maxOutputTokens: 2048
            }
        });

        let accumulated = "";
        for await (const chunk of responseStream) {
            if (chunk.text) {
                accumulated += chunk.text;
                res.write(`data: ${JSON.stringify({ text: chunk.text, fullText: accumulated })}\n\n`);
                if (typeof (res as any).flush === 'function') {
                    (res as any).flush();
                }
            }
        }

        res.write(`data: ${JSON.stringify({ type: "done", fullText: accumulated })}\n\n`);
        res.write(`data: [DONE]\n\n`);
        res.end();
    } catch (err: any) {
        if (!res.headersSent) {
            next(new AppError(`Gemini Live failure: ${err.message}`, 500, true, "LIVE_STREAMING_ERROR"));
        } else {
            res.write(`data: ${JSON.stringify({ error: err.message })}\n\n`);
            res.end();
        }
    }
});
