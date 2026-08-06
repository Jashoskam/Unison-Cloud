import { exec } from "child_process";
import path from "path";

export interface VerificationResult {
    success: boolean;
    command: string;
    durationMs: number;
    output: string;
    errors: string[];
}

export class VerificationAgent {
    public static async verifyBuild(cwd: string = process.cwd()): Promise<VerificationResult> {
        const start = Date.now();
        const isSwift = require("fs").existsSync(path.join(cwd, "Package.swift"));
        const command = isSwift ? "swift build 2>&1" : "npm test 2>&1";

        return new Promise((resolve) => {
            exec(command, { cwd }, (err, stdout, stderr) => {
                const durationMs = Date.now() - start;
                const rawOutput = (stdout || "") + "\n" + (stderr || "");
                const lines = rawOutput.split("\n");

                const errors: string[] = [];
                for (const line of lines) {
                    if (line.includes("error:") || line.includes("FAILED") || line.includes("ERR!")) {
                        errors.push(line.trim());
                    }
                }

                const success = !err && errors.length === 0;
                resolve({
                    success,
                    command,
                    durationMs,
                    output: rawOutput.slice(-3000),
                    errors
                });
            });
        });
    }
}
