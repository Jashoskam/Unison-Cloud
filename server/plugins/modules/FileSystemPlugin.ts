import fs from "fs";
import path from "path";
import { PluginDefinition } from "../PluginRegistry";

export const FileSystemPlugin: PluginDefinition = {
    name: "FileSystemPlugin",
    description: "Modular File System Operations for reading, writing, searching, and deleting local workspace files.",
    version: "1.0.0",
    tools: [
        {
            name: "fs_read_file",
            description: "Read the textual content of a file relative to workspace root.",
            schema: {
                type: "object",
                properties: {
                    filePath: { type: "string", description: "Relative file path (e.g., 'saved_files/notes.txt')" }
                },
                required: ["filePath"]
            },
            handler: async (args) => {
                const safePath = path.join(process.cwd(), path.normalize(args.filePath).replace(/^(\.\.[\/\\])+/, ''));
                if (!fs.existsSync(safePath)) {
                    return { error: `File not found at path: ${args.filePath}` };
                }
                const content = fs.readFileSync(safePath, "utf-8");
                return { filePath: args.filePath, content, sizeBytes: Buffer.byteLength(content) };
            }
        },
        {
            name: "fs_write_file",
            description: "Write or overwrite content to a file in workspace.",
            schema: {
                type: "object",
                properties: {
                    filePath: { type: "string", description: "Relative file path to save to" },
                    content: { type: "string", description: "Text content to write" }
                },
                required: ["filePath", "content"]
            },
            handler: async (args) => {
                const safePath = path.join(process.cwd(), path.normalize(args.filePath).replace(/^(\.\.[\/\\])+/, ''));
                const dir = path.dirname(safePath);
                if (!fs.existsSync(dir)) {
                    fs.mkdirSync(dir, { recursive: true });
                }
                fs.writeFileSync(safePath, args.content, "utf-8");
                return { success: true, filePath: args.filePath, bytesWritten: Buffer.byteLength(args.content) };
            }
        },
        {
            name: "fs_list_directory",
            description: "List files and subdirectories in a workspace directory.",
            schema: {
                type: "object",
                properties: {
                    dirPath: { type: "string", description: "Directory path relative to workspace root, e.g. '.' or 'src'" }
                },
                required: ["dirPath"]
            },
            handler: async (args) => {
                const targetDir = args.dirPath ? path.join(process.cwd(), args.dirPath) : process.cwd();
                if (!fs.existsSync(targetDir)) {
                    return { error: `Directory not found: ${args.dirPath}` };
                }
                const entries = fs.readdirSync(targetDir, { withFileTypes: true });
                const items = entries.map(e => ({
                    name: e.name,
                    isDirectory: e.isDirectory(),
                    size: e.isFile() ? fs.statSync(path.join(targetDir, e.name)).size : 0
                }));
                return { dirPath: args.dirPath || ".", itemsCount: items.length, items };
            }
        }
    ]
};
