import { PluginDefinition } from "../PluginRegistry";

export interface EmailMessage {
    id: string;
    threadId: string;
    from: string;
    to: string;
    subject: string;
    snippet: string;
    body: string;
    date: string;
    unread: boolean;
    labels: string[];
}

// In-memory persistent state for Gmail Inbox
const mockGmailInbox: EmailMessage[] = [
    {
        id: "msg_101",
        threadId: "thr_101",
        from: "security-kernel@google.com",
        to: "developer@unison.ai",
        subject: "Google Auth Token Expiry Alert & Workspace Sync",
        snippet: "The active OAuth2 session for Gmail & Google Workspace is verified on unison-cloud.onrender.com...",
        body: "Hello Developer,\n\nYour active OAuth2 session for Gmail & Google Workspace integrations is verified and active on https://unison-cloud.onrender.com.\n\nAll automated triggers and scheduled agent sweeps are active.\n\nRegards,\nGoogle Security Kernel",
        date: "Today, 09:15 AM",
        unread: true,
        labels: ["INBOX", "IMPORTANT", "SECURITY"]
    },
    {
        id: "msg_102",
        threadId: "thr_102",
        from: "sarah.jenkins@acme-corp.com",
        to: "developer@unison.ai",
        subject: "Q3 System Architecture Review & Render Server Benchmarks",
        snippet: "Hey team! I checked the new plugin registry and express modular endpoints on Render...",
        body: "Hi team,\n\nI reviewed the new modular plugin architecture on Render server. The execution logs and trace IDs look great!\nLet's schedule our sync tomorrow at 10 AM PST to finalize the scheduled task runner.\n\nBest,\nSarah Jenkins",
        date: "Yesterday, 4:30 PM",
        unread: true,
        labels: ["INBOX", "WORK"]
    },
    {
        id: "msg_103",
        threadId: "thr_103",
        from: "deployments@render.com",
        to: "developer@unison.ai",
        subject: "Deployment Successful: unison-cloud (Render)",
        snippet: "Your service unison-cloud on Render was built and deployed successfully. Health check 200 OK.",
        body: "Service: unison-cloud.onrender.com\nBranch: main\nCommit: feat: Enterprise Plugin Registry & Gmail Integration\nStatus: Live",
        date: "Aug 5, 2026",
        unread: false,
        labels: ["INBOX", "UPDATES"]
    }
];

export const GmailPlugin: PluginDefinition = {
    name: "GmailPlugin",
    description: "Official Gmail & Workspace integration plugin for listing emails, sending messages, searching threads, and creating drafts.",
    version: "1.0.0",
    tools: [
        {
            name: "gmail_list_messages",
            description: "Lists or searches emails in the user's Gmail inbox with filtering parameters.",
            schema: {
                type: "object",
                properties: {
                    query: { type: "string", description: "Search query filter (e.g. 'unread', 'from:sarah', 'Render', 'Security')" },
                    maxResults: { type: "string", description: "Maximum number of emails to return (default: 10)" }
                },
                required: []
            },
            handler: async (args) => {
                const q = (args.query || "").toLowerCase();
                const limit = parseInt(args.maxResults || "10", 10);
                
                let results = mockGmailInbox;
                if (q) {
                    results = results.filter(m => 
                        m.subject.toLowerCase().includes(q) || 
                        m.from.toLowerCase().includes(q) || 
                        m.snippet.toLowerCase().includes(q) ||
                        m.body.toLowerCase().includes(q)
                    );
                }
                
                return {
                    status: "SUCCESS",
                    queryExecuted: args.query || "ALL",
                    totalFound: results.length,
                    messages: results.slice(0, limit).map(m => ({
                        id: m.id,
                        from: m.from,
                        subject: m.subject,
                        date: m.date,
                        snippet: m.snippet,
                        unread: m.unread,
                        labels: m.labels
                    }))
                };
            }
        },
        {
            name: "gmail_get_message_details",
            description: "Fetches full body, headers, and thread details of a specific email message ID.",
            schema: {
                type: "object",
                properties: {
                    messageId: { type: "string", description: "Unique Gmail message ID (e.g., 'msg_101')" }
                },
                required: ["messageId"]
            },
            handler: async (args) => {
                const msg = mockGmailInbox.find(m => m.id === args.messageId);
                if (!msg) {
                    return { error: `Gmail message with ID '${args.messageId}' not found.` };
                }
                // Mark as read
                msg.unread = false;
                return {
                    status: "SUCCESS",
                    message: msg
                };
            }
        },
        {
            name: "gmail_send_email",
            description: "Sends a new email via user's Gmail account.",
            schema: {
                type: "object",
                properties: {
                    to: { type: "string", description: "Recipient email address" },
                    subject: { type: "string", description: "Email subject line" },
                    body: { type: "string", description: "Body text content of the email" }
                },
                required: ["to", "subject", "body"]
            },
            handler: async (args) => {
                const newMsg: EmailMessage = {
                    id: `msg_${Date.now()}`,
                    threadId: `thr_${Date.now()}`,
                    from: "me (developer@unison.ai)",
                    to: args.to,
                    subject: args.subject,
                    snippet: args.body.slice(0, 100) + "...",
                    body: args.body,
                    date: "Just now",
                    unread: false,
                    labels: ["SENT"]
                };
                mockGmailInbox.unshift(newMsg);

                return {
                    status: "SENT",
                    messageId: newMsg.id,
                    recipient: args.to,
                    subject: args.subject,
                    timestamp: new Date().toISOString()
                };
            }
        }
    ]
};
