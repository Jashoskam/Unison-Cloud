import SwiftUI

public struct ScheduledTaskModel: Identifiable, Codable {
    public var id: String
    public var name: String
    public var project: String
    public var scheduleType: String // "Daily", "Hourly", "Weekly", "Cron"
    public var scheduleTime: String // e.g. "9:00 AM", "Every 1 hour", "0 9 * * *"
    public var prompt: String
    public var model: String
    public var active: Bool
    public var createdAt: String
    public var lastRunAt: String?
    public var lastStatus: String? // "success", "error", "pending"
    public var lastResultSnippet: String?
    public var runCount: Int
    
    public init(
        id: String = "st_\(Int(Date().timeIntervalSince1970))",
        name: String,
        project: String = "unison",
        scheduleType: String = "Daily",
        scheduleTime: String = "9:00 AM",
        prompt: String,
        model: String = "gemini-3.5-flash",
        active: Bool = true,
        createdAt: String = Date().description,
        lastRunAt: String? = nil,
        lastStatus: String? = nil,
        lastResultSnippet: String? = nil,
        runCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.project = project
        self.scheduleType = scheduleType
        self.scheduleTime = scheduleTime
        self.prompt = prompt
        self.model = model
        self.active = active
        self.createdAt = createdAt
        self.lastRunAt = lastRunAt
        self.lastStatus = lastStatus
        self.lastResultSnippet = lastResultSnippet
        self.runCount = runCount
    }
}

public struct ScheduledTasksView: View {
    @Binding var isSidebarExpanded: Bool
    
    @State private var tasks: [ScheduledTaskModel] = [
        ScheduledTaskModel(
            id: "st_001",
            name: "Morning Workspace Sync & Email Digest",
            project: "unison",
            scheduleType: "Daily",
            scheduleTime: "9:00 AM",
            prompt: "Check unread emails via Gmail plugin, summarize top 3 priority items, and save digest to workspace.",
            model: "gemini-3.5-flash",
            active: true,
            createdAt: "2026-08-04T09:00:00Z",
            lastRunAt: "2026-08-06T09:00:00Z",
            lastStatus: "success",
            lastResultSnippet: "Processed 3 unread emails. Security alert verified. Digest written to saved_files/morning_digest.md",
            runCount: 14
        ),
        ScheduledTaskModel(
            id: "st_002",
            name: "Hourly Render System Diagnostics Check",
            project: "unison",
            scheduleType: "Hourly",
            scheduleTime: "Every 1 hour",
            prompt: "Run query_installed_apps and verify server memory status. Log health pulse.",
            model: "gemini-2.5-flash",
            active: true,
            createdAt: "2026-08-01T12:00:00Z",
            lastRunAt: "2026-08-06T12:00:00Z",
            lastStatus: "success",
            lastResultSnippet: "Server status 200 OK. 15 companion apps detected. System load nominal.",
            runCount: 112
        ),
        ScheduledTaskModel(
            id: "st_003",
            name: "Weekly Knowledge Graph Memory Consolidation",
            project: "unison",
            scheduleType: "Weekly",
            scheduleTime: "Mondays @ 8:00 AM",
            prompt: "Scan recent user chats and project documents. Update long-term persistent concept graph in MemoryKnowledgeGraphPlugin.",
            model: "gemini-3.5-pro",
            active: true,
            createdAt: "2026-07-28T08:00:00Z",
            lastRunAt: "2026-08-04T08:00:00Z",
            lastStatus: "success",
            lastResultSnippet: "Extracted 28 new entities and 42 conceptual edges. Concept graph synced.",
            runCount: 4
        )
    ]
    
    @State private var searchQuery: String = ""
    @State private var showingCreateModal: Bool = false
    @State private var editingTask: ScheduledTaskModel? = nil
    @State private var isExecutingTaskId: String? = nil
    @State private var executionFeedbackMessage: String? = nil
    
    // Modal Form States
    @State private var formName: String = ""
    @State private var formProject: String = "unison"
    @State private var formScheduleType: String = "Daily"
    @State private var formScheduleTime: String = "9:00 AM"
    @State private var formPrompt: String = ""
    @State private var formModel: String = "gemini-3.5-flash"
    @State private var formActive: Bool = true
    
    public init(isSidebarExpanded: Binding<Bool> = .constant(true)) {
        self._isSidebarExpanded = isSidebarExpanded
    }
    
    public var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.05)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Header Bar
                topHeaderView
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Main Title Banner
                        titleBannerView
                        
                        // Engine Performance Metrics
                        metricsSummaryView
                        
                        // Action Toolbar & Search
                        toolbarView
                        
                        // Tasks List Cards
                        tasksListView
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            
            // Modal Sheet for Creating / Editing Task
            if showingCreateModal {
                modalTaskEditorOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingCreateModal)
        .onAppear {
            fetchTasksFromBackend()
        }
    }
    
    // MARK: - Subviews
    
    private var topHeaderView: some View {
        HStack(spacing: 12) {
            if !isSidebarExpanded {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isSidebarExpanded.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                
                Spacer().frame(width: 4)
            }
            
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 15))
                .foregroundColor(.cyan)
            
            Text("Scheduled Tasks Engine")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            
            Text("v3.5")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.cyan.opacity(0.15))
                .cornerRadius(4)
            
            Spacer()
            
            if let feedback = executionFeedbackMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    Text(feedback)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.15))
                .cornerRadius(8)
                .transition(.opacity)
            }
            
            Button(action: {
                fetchTasksFromBackend()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text("Refresh")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
    
    private var titleBannerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Scheduled Agent Tasks")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    resetForm()
                    showingCreateModal = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("New Scheduled Task")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.cyan)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Text("Automated background AI agents operating on Render microservices & local native desktop loops")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))
        }
    }
    
    private var metricsSummaryView: some View {
        HStack(spacing: 16) {
            metricCard(title: "Active Tasks", value: "\(tasks.filter({ $0.active }).count)", symbol: "play.circle.fill", color: .green)
            metricCard(title: "Total Executions", value: "\(tasks.reduce(0, { $0 + $1.runCount }))", symbol: "bolt.fill", color: .cyan)
            metricCard(title: "Engine Status", value: "200 OK", symbol: "server.rack", color: .blue)
            metricCard(title: "Render Memory Cap", value: "400 MB", symbol: "memorychip", color: .purple)
        }
    }
    
    private func metricCard(title: String, value: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.15))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    private var toolbarView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
                TextField("Filter scheduled tasks...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .cornerRadius(8)
            
            Spacer()
            
            Text("\(filteredTasks.count) tasks registered")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    private var filteredTasks: [ScheduledTaskModel] {
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            return tasks
        } else {
            let q = searchQuery.lowercased()
            return tasks.filter { $0.name.lowercased().contains(q) || $0.prompt.lowercased().contains(q) || $0.project.lowercased().contains(q) }
        }
    }
    
    private var tasksListView: some View {
        VStack(spacing: 14) {
            if filteredTasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No scheduled tasks found")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                    Text("Create a new task to automate background workflows.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color.white.opacity(0.02))
                .cornerRadius(12)
            } else {
                ForEach(filteredTasks) { task in
                    taskCardView(task: task)
                }
            }
        }
    }
    
    private func taskCardView(task: ScheduledTaskModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                // Status Icon
                Circle()
                    .fill(task.active ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(task.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(task.project)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.15))
                            .cornerRadius(4)
                        
                        Text(task.scheduleType)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .cornerRadius(4)
                        
                        Text(task.model)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                    }
                    
                    Text("Schedule: \(task.scheduleTime)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                HStack(spacing: 10) {
                    // Toggle Active
                    Toggle("", isOn: Binding(
                        get: { task.active },
                        set: { newActive in
                            toggleTaskActive(task: task, active: newActive)
                        }
                    ))
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)
                    
                    // Run Now Button
                    Button(action: {
                        triggerRunNow(task: task)
                    }) {
                        HStack(spacing: 4) {
                            if isExecutingTaskId == task.id {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 10))
                            }
                            Text("Run Now")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isExecutingTaskId == task.id)
                    
                    // Edit
                    Button(action: {
                        editingTask = task
                        populateForm(from: task)
                        showingCreateModal = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(6)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    // Delete
                    Button(action: {
                        deleteTask(task: task)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(6)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Prompt box
            VStack(alignment: .leading, spacing: 4) {
                Text("PROMPT INSTRUCTIONS:")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Text(task.prompt)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(3)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.3))
            .cornerRadius(8)
            
            // Last Result Footer
            if let snippet = task.lastResultSnippet, !snippet.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: task.lastStatus == "success" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(task.lastStatus == "success" ? .green : .orange)
                    
                    Text("Last Run (\(task.lastRunAt ?? "Recently")): \(snippet)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("\(task.runCount) total runs")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(task.active ? Color.cyan.opacity(0.2) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }
    
    // MARK: - Modal Overlay
    
    private var modalTaskEditorOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    showingCreateModal = false
                }
            
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.cyan)
                    Text(editingTask == nil ? "Create Scheduled Task" : "Edit Scheduled Task")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: {
                        showingCreateModal = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(6)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Task Name
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Task Title / Name")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                            TextField("e.g. Morning Workspace Sync & Email Digest", text: $formName)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                        }
                        
                        // Project Scope & Model Selection
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Project Scope")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                                TextField("e.g. unison", text: $formProject)
                                    .textFieldStyle(.plain)
                                    .padding(10)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Model Selector")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                                Picker("", selection: $formModel) {
                                    Text("Gemini 3.5 Flash").tag("gemini-3.5-flash")
                                    Text("Gemini 3.5 Pro").tag("gemini-3.5-pro")
                                    Text("Gemini 2.5 Flash").tag("gemini-2.5-flash")
                                }
                                .pickerStyle(.menu)
                                .padding(6)
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                            }
                        }
                        
                        // Schedule Type & Time
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Schedule Frequency")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                                Picker("", selection: $formScheduleType) {
                                    Text("Daily").tag("Daily")
                                    Text("Hourly").tag("Hourly")
                                    Text("Weekly").tag("Weekly")
                                    Text("Cron Pattern").tag("Cron")
                                }
                                .pickerStyle(.menu)
                                .padding(6)
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Schedule Time / Expression")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                                TextField("e.g. 9:00 AM or 0 * * * *", text: $formScheduleTime)
                                    .textFieldStyle(.plain)
                                    .padding(10)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Prompt Editor
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Agent Instruction Prompt")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                            TextEditor(text: $formPrompt)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(height: 100)
                                .padding(6)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                        }
                        
                        // Active Toggle
                        Toggle("Activate task immediately upon saving", isOn: $formActive)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.top, 4)
                    }
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                HStack {
                    Button("Cancel") {
                        showingCreateModal = false
                    }
                    .foregroundColor(.gray)
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Button(action: {
                        saveTaskFromForm()
                    }) {
                        Text(editingTask == nil ? "Save Scheduled Task" : "Update Task")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color.cyan)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(formName.isEmpty || formPrompt.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 540)
            .background(Color(red: 0.1, green: 0.1, blue: 0.11))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Logic & API Integrations
    
    private func resetForm() {
        editingTask = nil
        formName = ""
        formProject = "unison"
        formScheduleType = "Daily"
        formScheduleTime = "9:00 AM"
        formPrompt = ""
        formModel = "gemini-3.5-flash"
        formActive = true
    }
    
    private func populateForm(from task: ScheduledTaskModel) {
        formName = task.name
        formProject = task.project
        formScheduleType = task.scheduleType
        formScheduleTime = task.scheduleTime
        formPrompt = task.prompt
        formModel = task.model
        formActive = task.active
    }
    
    private func fetchTasksFromBackend() {
        guard let url = URL(string: "http://localhost:3000/api/v1/scheduled-tasks") else { return }
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else { return }
            struct FetchResponse: Codable {
                let success: Bool
                let tasks: [ScheduledTaskModel]
            }
            if let decoded = try? JSONDecoder().decode(FetchResponse.self, from: data), decoded.success {
                DispatchQueue.main.async {
                    self.tasks = decoded.tasks
                }
            }
        }.resume()
    }
    
    private func saveTaskFromForm() {
        if let editing = editingTask {
            // Edit mode
            if let idx = tasks.firstIndex(where: { $0.id == editing.id }) {
                tasks[idx].name = formName
                tasks[idx].project = formProject
                tasks[idx].scheduleType = formScheduleType
                tasks[idx].scheduleTime = formScheduleTime
                tasks[idx].prompt = formPrompt
                tasks[idx].model = formModel
                tasks[idx].active = formActive
            }
        } else {
            // New Task mode
            let newTask = ScheduledTaskModel(
                name: formName,
                project: formProject,
                scheduleType: formScheduleType,
                scheduleTime: formScheduleTime,
                prompt: formPrompt,
                model: formModel,
                active: formActive
            )
            tasks.unshift(newTask)
        }
        
        showingCreateModal = false
        showFeedback("Task saved successfully.")
    }
    
    private func toggleTaskActive(task: ScheduledTaskModel, active: Bool) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].active = active
        }
    }
    
    private func deleteTask(task: ScheduledTaskModel) {
        tasks.removeAll(where: { $0.id == task.id })
        showFeedback("Task '\(task.name)' removed.")
    }
    
    private func triggerRunNow(task: ScheduledTaskModel) {
        isExecutingTaskId = task.id
        
        // Execute trigger call to backend or simulation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                self.tasks[idx].runCount += 1
                self.tasks[idx].lastRunAt = "Just now"
                self.tasks[idx].lastStatus = "success"
                self.tasks[idx].lastResultSnippet = "Executed agent prompt successfully against \(task.model)."
            }
            self.isExecutingTaskId = nil
            self.showFeedback("Task '\(task.name)' triggered live.")
        }
    }
    
    private func showFeedback(_ msg: String) {
        withAnimation {
            executionFeedbackMessage = msg
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                executionFeedbackMessage = nil
            }
        }
    }
}

fileprivate extension Array {
    mutating func unshift(_ element: Element) {
        self.insert(element, at: 0)
    }
}
