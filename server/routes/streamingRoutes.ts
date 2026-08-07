import { Router, Request, Response, NextFunction } from "express";
import { GoogleGenAI } from "@google/genai";
import { spawn, ChildProcess } from "child_process";
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

// Helper function to truncate stdout/stderr logs for Gemini Context (Head 20 + Tail 50)
const truncateLogBufferForContext = (logs: string[]): string => {
    if (logs.length <= 70) {
        return logs.join("\n");
    }
    const head = logs.slice(0, 20);
    const tail = logs.slice(logs.length - 50);
    const omittedCount = logs.length - 70;
    return [...head, `\n[... Omitted ${omittedCount} lines of build/terminal output for token preservation ...]\n`, ...tail].join("\n");
};

// Maximum agentic execution ceiling
const MAX_AGENT_LOOPS = 15;

streamingRouter.post("/agent-loop", async (req: Request, res: Response, next: NextFunction) => {
    const requestId = `req_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    let activeSubprocess: ChildProcess | null = null;
    let isClientConnected = true;

    // Attach req.on('close') process cancellation listener (SIGTERM)
    req.on("close", () => {
        isClientConnected = false;
        if (activeSubprocess && !activeSubprocess.killed) {
            console.log(`[Agent Loop ${requestId}] Client disconnected. Terminating child process (SIGTERM)...`);
            try {
                activeSubprocess.kill("SIGTERM");
                setTimeout(() => {
                    if (activeSubprocess && !activeSubprocess.killed) {
                        activeSubprocess.kill("SIGKILL");
                    }
                }, 2000);
            } catch (e) {
                console.error(`[Agent Loop ${requestId}] Error killing process:`, e);
            }
        }
    });

    try {
        const { message, modelName, prompt, cwd } = req.body;
        const textPrompt = prompt || message;
        const workingDir = cwd || process.cwd();

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
        const systemInstruction = `You are Unison OS Agentic Engineer, a world-class AI developer operating in an autonomous loop.
You can execute shell commands, read files, write code, and debug issues.
When thinking through complex code architectures, express your internal reasoning step by step.`;

        const googleGenAI = getGenAIClient();
        let loopCounter = 0;
        let finalResponseText = "";

        console.log(`[Agent Loop ${requestId}] Starting stream session with model: ${targetModel}`);

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
            if (!isClientConnected) break;

            const candidates = (chunk as any).candidates;
            if (candidates && candidates[0] && candidates[0].content && candidates[0].content.parts) {
                for (const part of candidates[0].content.parts) {
                    // 1. Thinking / Reasoning delta
                    if (part.thought || part.thinking) {
                        const thoughtText = part.thought || part.thinking;
                        res.write(`data: ${JSON.stringify({ type: "thought_delta", thought: thoughtText })}\n\n`);
                        if (typeof (res as any).flush === 'function') (res as any).flush();
                    }
                    // 2. Standard Text output delta
                    if (part.text) {
                        finalResponseText += part.text;
                        res.write(`data: ${JSON.stringify({ type: "text_delta", text: part.text })}\n\n`);
                        if (typeof (res as any).flush === 'function') (res as any).flush();
                    }
                }
            } else if (chunk.text) {
                finalResponseText += chunk.text;
                res.write(`data: ${JSON.stringify({ type: "text_delta", text: chunk.text })}\n\n`);
                if (typeof (res as any).flush === 'function') (res as any).flush();
            }
        }

        res.write(`data: ${JSON.stringify({ type: "done", fullText: finalResponseText })}\n\n`);
        res.write(`data: [DONE]\n\n`);
        res.end();

    } catch (err: any) {
        console.error(`[Agent Loop ${requestId}] Error:`, err);
        const isQuotaError = err.message?.includes("429") || err.message?.includes("Quota") || err.message?.includes("RESOURCE_EXHAUSTED");
        const payload = {
            type: "quota_error",
            code: isQuotaError ? 429 : 500,
            message: err.message || "An unexpected error occurred during agentic loop execution."
        };
        if (!res.headersSent) {
            res.setHeader("Content-Type", "text/event-stream");
            res.write(`data: ${JSON.stringify(payload)}\n\n`);
            res.write(`data: [DONE]\n\n`);
            res.end();
        } else {
            res.write(`data: ${JSON.stringify(payload)}\n\n`);
            res.write(`data: [DONE]\n\n`);
            res.end();
        }
    }
});

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
