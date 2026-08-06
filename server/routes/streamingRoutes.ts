import { Router, Request, Response, NextFunction } from "express";
import { GoogleGenAI } from "@google/genai";
import { AppError } from "../middleware/errorHandler";

export const streamingRouter = Router();

const googleGenAI = new GoogleGenAI({
    apiKey: process.env.GEMINI_API_KEY || "",
    httpOptions: {
        headers: {
            'User-Agent': 'aistudio-build'
        }
    }
});

streamingRouter.post("/chat", async (req: Request, res: Response, next: NextFunction) => {
    try {
        const { message, modelName, prompt } = req.body;
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

        const targetModel = modelName || "gemini-2.5-flash";
        console.log(`[Streaming Route] Streaming prompt to '${targetModel}'`);

        const systemInstruction = `You are Unison OS, an advanced AI-native desktop operating system and coding workspace. You are a world-class software engineer, systems architect, and technical writer.

STRICT INDUSTRIAL EXECUTION LOG PROTOCOL (ANTIGRAVITY / CURSOR STANDARDS):
1. ALWAYS begin every response with a [THOUGHTS]...[/THOUGHTS] block before emitting any final text or code.
2. Inside [THOUGHTS], structure your exact exploration and file modifications step-by-step using these precise single-line activity items:
   Worked for {duration_seconds}s
   Explored {file_count} files, {folder_count} folders

   Thought for 1s
   Analyzed 📁 {folder_path}
   Analyzed 📄 {file_name}#L{start_line}-{end_line}
   Thought for 1s
   Crafting {file_name}
   Edited 📄 {file_name} +{additions} -{deletions}
   Analyzed 📄 {file_name}#L1-{total_lines}

3. NO EMOJIS IN FINAL TEXT OR TITLES: Use clean text formatting and SF Symbol vector graphics.
4. CODE MUTATION: When generating code files, ALWAYS output complete executable code wrapped in fenced blocks with explicit filename headers (e.g. \`\`\`cpp blink2.ino or \`\`\`cpp ServoControl.ino).
5. At the absolute end of your response, provide 3 relevant follow-up questions using: [FOLLOW_UPS: ["Q1", "Q2", "Q3"]].`;

        const responseStream = await googleGenAI.models.generateContentStream({
            model: targetModel,
            contents: textPrompt,
            config: {
                systemInstruction,
                temperature: 0.2,
                maxOutputTokens: 32768,
                ...(targetModel.includes("2.5") ? { thinkingConfig: { thinkingBudget: 8192 } } : {})
            }
        });

        for await (const chunk of responseStream) {
            if (chunk.text) {
                res.write(`data: ${JSON.stringify({ text: chunk.text })}\n\n`);
                if (typeof (res as any).flush === 'function') {
                    (res as any).flush();
                }
            }
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
