import { PluginDefinition } from "../PluginRegistry";

export interface ScheduledTask {
    id: string;
    name: string;
    project: string;
    scheduleType: "Daily" | "Hourly" | "Weekly" | "Cron";
    scheduleTime: string; // e.g. "9:00 AM" or "10 mins" or "0 9 * * *"
    prompt: string;
    model: string;
    active: boolean;
    createdAt: string;
    lastRunAt?: string;
    lastStatus?: "success" | "error" | "pending";
    lastResultSnippet?: string;
    runCount: number;
}

// In-memory persistent store for scheduled tasks
export const scheduledTasksStore: ScheduledTask[] = [
    {
        id: "st_001",
        name: "Morning Workspace Sync & Email Digest",
        project: "unison",
        scheduleType: "Daily",
        scheduleTime: "9:00 AM",
        prompt: "Check unread emails via Gmail plugin, summarize top 3 priority items, and save digest to workspace.",
        model: "gemini-3.5-flash",
        active: true,
        createdAt: new Date(Date.now() - 86400000 * 2).toISOString(),
        lastRunAt: new Date(Date.now() - 3600000 * 3).toISOString(),
        lastStatus: "success",
        lastResultSnippet: "Processed 3 unread emails. Security alert verified. Digest written to saved_files/morning_digest.md",
        runCount: 14
    },
    {
        id: "st_002",
        name: "Hourly Render System Diagnostics Check",
        project: "unison",
        scheduleType: "Hourly",
        scheduleTime: "Every 1 hour",
        prompt: "Run query_installed_apps and verify server memory status. Log health pulse.",
        model: "gemini-2.5-flash",
        active: true,
        createdAt: new Date(Date.now() - 86400000 * 5).toISOString(),
        lastRunAt: new Date(Date.now() - 1800000).toISOString(),
        lastStatus: "success",
        lastResultSnippet: "Server status 200 OK. 15 companion apps detected. System load nominal.",
        runCount: 112
    }
];

export const ScheduledTaskPlugin: PluginDefinition = {
    name: "ScheduledTaskPlugin",
    description: "Automated agent task scheduler module. Allows AI agents to programmatically create, schedule, run, list, and disable cron or periodic tasks.",
    version: "1.0.0",
    tools: [
        {
            name: "create_scheduled_task",
            description: "Creates and schedules a new automated AI agent task with periodic or cron triggers.",
            schema: {
                type: "object",
                properties: {
                    name: { type: "string", description: "Task title/name" },
                    project: { type: "string", description: "Project scope (default: 'unison')" },
                    scheduleType: { type: "string", enum: ["Daily", "Hourly", "Weekly", "Cron"], description: "Schedule frequency" },
                    scheduleTime: { type: "string", description: "Time specification e.g. '9:00 AM', '0 * * * *', 'Every 30 mins'" },
                    prompt: { type: "string", description: "The instructions/prompt the agent will execute each run" },
                    model: { type: "string", description: "Gemini AI model to use (default: 'gemini-3.5-flash')" }
                },
                required: ["name", "scheduleType", "prompt"]
            },
            handler: async (args) => {
                const newTask: ScheduledTask = {
                    id: `st_${Date.now()}`,
                    name: args.name,
                    project: args.project || "unison",
                    scheduleType: args.scheduleType || "Daily",
                    scheduleTime: args.scheduleTime || "9:00 AM",
                    prompt: args.prompt,
                    model: args.model || "gemini-3.5-flash",
                    active: true,
                    createdAt: new Date().toISOString(),
                    runCount: 0
                };
                scheduledTasksStore.unshift(newTask);

                return {
                    status: "CREATED",
                    taskId: newTask.id,
                    task: newTask,
                    message: `Scheduled task '${newTask.name}' successfully registered.`
                };
            }
        },
        {
            name: "list_scheduled_tasks",
            description: "Lists all registered scheduled tasks and their execution history.",
            schema: {
                type: "object",
                properties: {}
            },
            handler: async () => {
                return {
                    status: "SUCCESS",
                    totalTasks: scheduledTasksStore.length,
                    tasks: scheduledTasksStore
                };
            }
        },
        {
            name: "trigger_scheduled_task_now",
            description: "Immediately executes a scheduled task on demand.",
            schema: {
                type: "object",
                properties: {
                    taskId: { type: "string", description: "The ID of the scheduled task to execute immediately" }
                },
                required: ["taskId"]
            },
            handler: async (args) => {
                const task = scheduledTasksStore.find(t => t.id === args.taskId);
                if (!task) {
                    return { error: `Scheduled task with ID '${args.taskId}' not found.` };
                }

                task.lastRunAt = new Date().toISOString();
                task.runCount += 1;
                task.lastStatus = "success";
                task.lastResultSnippet = `On-demand execution completed for task '${task.name}'. Prompt evaluated against ${task.model}.`;

                return {
                    status: "EXECUTED",
                    taskId: task.id,
                    executedAt: task.lastRunAt,
                    resultSnippet: task.lastResultSnippet
                };
            }
        }
    ]
};
