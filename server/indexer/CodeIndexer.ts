import fs from "fs";
import path from "path";

export interface SymbolLocation {
    filePath: string;
    symbolName: string;
    kind: "class" | "struct" | "function" | "interface" | "protocol" | "import" | "variable";
    startLine: number;
    endLine: number;
    snippet: string;
}

export interface SearchResult {
    filePath: string;
    score: number;
    matches: SymbolLocation[];
}

export class CodeIndexer {
    private static instance: CodeIndexer;
    private symbolIndex: SymbolLocation[] = [];
    private isIndexing = false;
    private workspacePath = process.cwd();

    private constructor() {}

    public static getInstance(): CodeIndexer {
        if (!CodeIndexer.instance) {
            CodeIndexer.instance = new CodeIndexer();
        }
        return CodeIndexer.instance;
    }

    public async indexWorkspace(workspaceDir: string = process.cwd()): Promise<{ indexedFiles: number; totalSymbols: number }> {
        if (this.isIndexing) return { indexedFiles: 0, totalSymbols: this.symbolIndex.length };
        this.isIndexing = true;
        this.workspacePath = workspaceDir;
        this.symbolIndex = [];

        let indexedCount = 0;
        try {
            const files = this.collectFiles(workspaceDir);
            for (const filePath of files) {
                try {
                    const content = fs.readFileSync(filePath, "utf-8");
                    const symbols = this.parseSymbols(filePath, content);
                    this.symbolIndex.push(...symbols);
                    indexedCount++;
                } catch (_) {}
            }
        } finally {
            this.isIndexing = false;
        }

        console.log(`[CodeIndexer] Indexing complete: ${indexedCount} files, ${this.symbolIndex.length} AST symbols.`);
        return { indexedFiles: indexedCount, totalSymbols: this.symbolIndex.length };
    }

    private collectFiles(dir: string, fileList: string[] = []): string[] {
        if (!fs.existsSync(dir)) return fileList;
        const entries = fs.readdirSync(dir, { withFileTypes: true });

        for (const entry of entries) {
            const fullPath = path.join(dir, entry.name);
            if (entry.isDirectory()) {
                if (["node_modules", ".git", ".build", ".gemini", "dist", "out"].includes(entry.name)) continue;
                this.collectFiles(fullPath, fileList);
            } else if (entry.isFile()) {
                const ext = path.extname(entry.name).toLowerCase();
                if ([".swift", ".ts", ".js", ".py", ".rs", ".cpp", ".h", ".c", ".go", ".md", ".json"].includes(ext)) {
                    fileList.push(fullPath);
                }
            }
        }
        return fileList;
    }

    private parseSymbols(filePath: string, content: string): SymbolLocation[] {
        const symbols: SymbolLocation[] = [];
        const lines = content.split("\n");
        const relPath = path.relative(this.workspacePath, filePath);

        const regexes = [
            { kind: "class", regex: /(?:class|struct|enum|actor|protocol)\s+([A-Za-z0-9_]+)/g },
            { kind: "function", regex: /(?:func|function|def|void|int|async func)\s+([A-Za-z0-9_]+)/g },
            { kind: "interface", regex: /(?:interface|type)\s+([A-Za-z0-9_]+)/g },
            { kind: "import", regex: /(?:import|require|from)\s+([A-Za-z0-9_./"']+)/g }
        ];

        for (let lineIdx = 0; lineIdx < lines.length; lineIdx++) {
            const line = lines[lineIdx];

            for (const { kind, regex } of regexes) {
                regex.lastIndex = 0;
                let match;
                while ((match = regex.exec(line)) !== null) {
                    const symbolName = match[1];
                    if (!symbolName || symbolName.length < 2) continue;

                    const startLine = lineIdx + 1;
                    const endLine = Math.min(lines.length, startLine + 15);
                    const snippet = lines.slice(lineIdx, endLine).join("\n");

                    symbols.push({
                        filePath: relPath,
                        symbolName,
                        kind: kind as any,
                        startLine,
                        endLine,
                        snippet
                    });
                }
            }
        }
        return symbols;
    }

    public searchCodebase(query: string, limit: number = 15): SearchResult[] {
        if (!query.trim()) return [];
        const terms = query.toLowerCase().split(/\s+/).filter(t => t.length > 1);

        const resultsMap = new Map<string, { score: number; matches: SymbolLocation[] }>();

        for (const symbol of this.symbolIndex) {
            let score = 0;
            const symName = symbol.symbolName.toLowerCase();
            const pathName = symbol.filePath.toLowerCase();
            const snippetText = symbol.snippet.toLowerCase();

            for (const term of terms) {
                if (symName === term) score += 10;
                else if (symName.includes(term)) score += 5;
                if (pathName.includes(term)) score += 3;
                if (snippetText.includes(term)) score += 1;
            }

            if (score > 0) {
                const existing = resultsMap.get(symbol.filePath) || { score: 0, matches: [] };
                existing.score += score;
                if (!existing.matches.some(m => m.symbolName === symbol.symbolName && m.startLine === symbol.startLine)) {
                    existing.matches.push(symbol);
                }
                resultsMap.set(symbol.filePath, existing);
            }
        }

        const sorted = Array.from(resultsMap.entries())
            .map(([filePath, data]) => ({ filePath, score: data.score, matches: data.matches.slice(0, 5) }))
            .sort((a, b) => b.score - a.score);

        return sorted.slice(0, limit);
    }
}
