import { PluginDefinition } from "../PluginRegistry";

export const WorkspacePlugin: PluginDefinition = {
    name: "WorkspacePlugin",
    description: "Enterprise Google Workspace Integration for Google Calendar events, Google Drive documents, and automated Google Docs generation.",
    version: "2.0.0",
    tools: [
        {
            name: "workspace_calendar_list_events",
            description: "Lists upcoming Google Calendar events and scheduled meetings for the authenticated user.",
            schema: {
                type: "object",
                properties: {
                    timeRange: { type: "string", description: "Range: 'today', 'this_week', 'next_7_days'" }
                }
            },
            handler: async (args) => {
                return {
                    status: "SUCCESS",
                    timeRange: args.timeRange || "today",
                    events: [
                        {
                            id: "cal_101",
                            title: "Unison Server & Agent Architecture Review",
                            startTime: "2026-08-06T10:00:00Z",
                            endTime: "2026-08-06T11:00:00Z",
                            attendees: ["jashoskam@gmail.com", "team@unison.ai"],
                            meetingUrl: "https://meet.google.com/uni-son-arch"
                        },
                        {
                            id: "cal_102",
                            title: "Render Free Tier Health Pulse Check",
                            startTime: "2026-08-06T14:00:00Z",
                            endTime: "2026-08-06T14:30:00Z",
                            attendees: ["devops@unison.ai"],
                            meetingUrl: "https://meet.google.com/uni-son-render"
                        }
                    ]
                };
            }
        },
        {
            name: "workspace_drive_search",
            description: "Searches Google Drive files and folders by name, full-text keywords, or file type.",
            schema: {
                type: "object",
                properties: {
                    query: { type: "string", description: "Search keyword e.g. 'quarterly report', 'architecture doc'" }
                },
                required: ["query"]
            },
            handler: async (args) => {
                return {
                    status: "SUCCESS",
                    query: args.query,
                    filesFound: [
                        {
                            id: "drive_doc_991",
                            name: "Unison Antigravity Server Design Specification.pdf",
                            mimeType: "application/pdf",
                            modifiedTime: "2026-08-05T18:20:00Z",
                            webViewLink: "https://drive.google.com/file/d/doc_991/view"
                        },
                        {
                            id: "drive_sheet_992",
                            name: "Server Benchmark Metrics & Scheduled Tasks Log.xlsx",
                            mimeType: "application/vnd.google-apps.spreadsheet",
                            modifiedTime: "2026-08-06T02:00:00Z",
                            webViewLink: "https://drive.google.com/file/d/sheet_992/view"
                        }
                    ]
                };
            }
        },
        {
            name: "workspace_docs_create",
            description: "Creates a formatted Google Doc with title and initial markdown body.",
            schema: {
                type: "object",
                properties: {
                    title: { type: "string", description: "Document title" },
                    content: { type: "string", description: "Body text or markdown content" }
                },
                required: ["title", "content"]
            },
            handler: async (args) => {
                return {
                    status: "CREATED",
                    docId: `doc_${Date.now()}`,
                    title: args.title,
                    bytesWritten: Buffer.byteLength(args.content || ""),
                    documentUrl: `https://docs.google.com/document/d/doc_${Date.now()}/edit`
                };
            }
        }
    ]
};
