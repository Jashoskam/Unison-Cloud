import Foundation

/// Swift models representing study materials/courses saved in Supabase & Firestore
public struct CourseMaterial: Identifiable, Codable, Hashable {
    public var id: String
    public var title: String
    public var author: String
    public var totalPages: Int
    public var category: String // "Course" or "Jupyter Notebook"
    public var coverColor: String
    public var mainContentStartPage: Int
    public var isCustom: Bool
    public var rawText: String?
    public var notebookCells: [NotebookCell]?
    public var isSynced: Bool? = true
    
    // Explicit decodables for serialized 'rawText' content (for Courses)
    public var documentHtml: String?
    public var checklist: [CourseChecklistItem]?
    public var dailyLogs: [CourseDailyLogItem]?
    public var mindmapNodes: [CourseMindmapNode]?
    public var mindmapEdges: [CourseMindmapEdge]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case totalPages = "total_pages"
        case category
        case coverColor = "cover_color"
        case mainContentStartPage = "main_content_start_page"
        case isCustom = "is_custom"
        case rawText = "raw_text"
        case notebookCells = "notebook_cells"
        case isSynced = "is_synced"
        
        // Decoded fields
        case documentHtml
        case checklist
        case dailyLogs
        case mindmapNodes
        case mindmapEdges
    }
    
    public init(
        id: String = "course_custom_\(Int64(Date().timeIntervalSince1970 * 1000))",
        title: String,
        author: String = "AI Scholar",
        totalPages: Int = 1,
        category: String = "Course",
        coverColor: String = "from-indigo-950 via-[#0A0B0F] to-slate-900 border-indigo-500/20",
        mainContentStartPage: Int = 1,
        isCustom: Bool = true,
        rawText: String? = nil,
        notebookCells: [NotebookCell]? = nil,
        isSynced: Bool? = true,
        documentHtml: String? = nil,
        checklist: [CourseChecklistItem]? = nil,
        dailyLogs: [CourseDailyLogItem]? = nil,
        mindmapNodes: [CourseMindmapNode]? = nil,
        mindmapEdges: [CourseMindmapEdge]? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.totalPages = totalPages
        self.category = category
        self.coverColor = coverColor
        self.mainContentStartPage = mainContentStartPage
        self.isCustom = isCustom
        self.rawText = rawText
        self.notebookCells = notebookCells
        self.isSynced = isSynced
        self.documentHtml = documentHtml
        self.checklist = checklist
        self.dailyLogs = dailyLogs
        self.mindmapNodes = mindmapNodes
        self.mindmapEdges = mindmapEdges
    }
}

public struct NotebookCell: Codable, Hashable {
    public var id: String?
    public var cell_type: String // code, markdown
    public var source: String
    public var outputs: [String]?
    
    public init(id: String? = nil, cell_type: String, source: String, outputs: [String]? = nil) {
        self.id = id
        self.cell_type = cell_type
        self.source = source
        self.outputs = outputs
    }
}

public struct CourseChecklistItem: Identifiable, Codable, Hashable {
    public var id: String
    public var text: String
    public var done: Bool
    
    public init(id: String = "chk_\(UUID().uuidString)", text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }
}

public struct CourseDailyLogItem: Identifiable, Codable, Hashable {
    public var id: String
    public var date: String
    public var content: String
    
    public init(id: String = "log_\(UUID().uuidString)", date: String, content: String) {
        self.id = id
        self.date = date
        self.content = content
    }
}

public struct CourseMindmapNode: Identifiable, Codable, Hashable {
    public var id: String
    public var text: String
    public var x: Double
    public var y: Double
    public var color: String?
    
    public init(id: String = "node_\(UUID().uuidString)", text: String, x: Double, y: Double, color: String? = nil) {
        self.id = id
        self.text = text
        self.x = x
        self.y = y
        self.color = color
    }
}

public struct CourseMindmapEdge: Identifiable, Codable, Hashable {
    public var id: String
    public var from: String
    public var to: String
    
    public init(id: String = "edge_\(UUID().uuidString)", from: String, to: String) {
        self.id = id
        self.from = from
        self.to = to
    }
}
