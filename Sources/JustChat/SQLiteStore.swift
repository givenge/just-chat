import Foundation
import SQLite3

final class SQLiteStore {
  private var db: OpaquePointer?
  private let path: String

  init(path: String) {
    self.path = path
  }

  deinit {
    sqlite3_close(db)
  }

  func open() throws {
    if sqlite3_open(path, &db) != SQLITE_OK {
      throw SQLiteStoreError.open(message: lastErrorMessage)
    }
    try migrate()
  }

  func createConversation(title: String, assistantId: UUID? = nil) throws -> Conversation {
    let conversation = Conversation(
      id: UUID(), title: title, assistantId: assistantId, createdAt: Date(), updatedAt: Date())
    try execute(
      """
      INSERT INTO conversations (id, title, assistant_id, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
      """,
      [
        conversation.id.uuidString,
        conversation.title,
        conversation.assistantId?.uuidString,
        conversation.createdAt.timeIntervalSince1970,
        conversation.updatedAt.timeIntervalSince1970,
      ]
    )
    return conversation
  }

  func listConversations() throws -> [Conversation] {
    try query(
      "SELECT id, title, assistant_id, created_at, updated_at FROM conversations ORDER BY updated_at DESC"
    ) { statement in
      Conversation(
        id: UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))) ?? UUID(),
        title: String(cString: sqlite3_column_text(statement, 1)),
        assistantId: optionalUUID(statement, 2),
        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
        updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
      )
    }
  }

  func updateConversationTitle(id: UUID, title: String) throws {
    try execute(
      """
      UPDATE conversations SET title = ?, updated_at = ? WHERE id = ?
      """,
      [title, Date().timeIntervalSince1970, id.uuidString]
    )
  }

  func deleteConversation(id: UUID) throws {
    try execute("DELETE FROM messages WHERE conversation_id = ?", [id.uuidString])
    try execute("DELETE FROM conversations WHERE id = ?", [id.uuidString])
  }

  func saveProviders(_ providers: [ModelProvider]) throws {
    try execute("DELETE FROM providers")
    for provider in providers {
      let modelsData = try JSONEncoder().encode(provider.models)
      let visionModelsData = try JSONEncoder().encode(provider.visionModels.sorted())
      try execute(
        """
        INSERT INTO providers (id, provider_type, kind, name, base_url, api_key_name, api_key, models_json, vision_models_json, default_model, is_enabled)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
          provider.id.uuidString,
          provider.providerType.rawValue,
          provider.kind.rawValue,
          provider.name,
          provider.baseURL.absoluteString,
          "",
          provider.apiKey,
          String(data: modelsData, encoding: .utf8) ?? "[]",
          String(data: visionModelsData, encoding: .utf8) ?? "[]",
          provider.defaultModel,
          true,
        ]
      )
    }
  }

  func listProviders() throws -> [ModelProvider] {
    try query(
      """
      SELECT id, provider_type, kind, name, base_url, api_key, models_json, vision_models_json, default_model
      FROM providers
      ORDER BY rowid ASC
      """
    ) { statement in
      let name = String(cString: sqlite3_column_text(statement, 3))
      let kind =
        ProviderKind(rawValue: String(cString: sqlite3_column_text(statement, 2)))
        ?? .openAIResponses
      let providerTypeText = optionalString(statement, 1)
      let providerType =
        providerTypeText.flatMap(ProviderCatalogType.init(rawValue:))
        ?? inferProviderType(name: name, kind: kind)
      let modelsText = String(cString: sqlite3_column_text(statement, 6))
      let models = (try? JSONDecoder().decode([String].self, from: Data(modelsText.utf8))) ?? []
      let visionModelsText = optionalString(statement, 7) ?? "[]"
      let visionModels = Set(
        (try? JSONDecoder().decode([String].self, from: Data(visionModelsText.utf8))) ?? [])
      return ModelProvider(
        id: UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))) ?? UUID(),
        providerType: providerType,
        kind: kind,
        name: name,
        baseURL: URL(string: String(cString: sqlite3_column_text(statement, 4))) ?? URL(
          string: "https://api.openai.com/v1")!,
        apiKey: optionalString(statement, 5) ?? "",
        models: models,
        visionModels: visionModels,
        defaultModel: String(cString: sqlite3_column_text(statement, 8))
      )
    }
  }

  func saveAssistants(_ assistants: [AssistantProfile]) throws {
    try execute("DELETE FROM assistants")
    for assistant in assistants {
      let templatesData = try JSONEncoder().encode(assistant.quickTemplates)
      try execute(
        """
        INSERT INTO assistants (
          id, name, system_prompt, provider_id, model_id, temperature,
          max_tokens, is_web_search_enabled, templates_json, context_message_count, reasoning_effort
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
          assistant.id.uuidString,
          assistant.name,
          assistant.systemPrompt,
          assistant.providerId?.uuidString,
          assistant.modelId,
          assistant.temperature,
          assistant.maxTokens,
          assistant.isWebSearchEnabled,
          String(data: templatesData, encoding: .utf8) ?? "[]",
          assistant.contextMessageCount,
          assistant.reasoningEffort.rawValue,
        ]
      )
    }
  }

  func listAssistants() throws -> [AssistantProfile] {
    try query(
      """
      SELECT id, name, system_prompt, provider_id, model_id, temperature, max_tokens, is_web_search_enabled, templates_json, context_message_count, reasoning_effort
      FROM assistants
      ORDER BY rowid ASC
      """
    ) { statement in
      let templatesText = String(cString: sqlite3_column_text(statement, 8))
      let templates =
        (try? JSONDecoder().decode([PromptTemplate].self, from: Data(templatesText.utf8))) ?? []
      return AssistantProfile(
        id: UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))) ?? UUID(),
        name: String(cString: sqlite3_column_text(statement, 1)),
        systemPrompt: String(cString: sqlite3_column_text(statement, 2)),
        providerId: optionalUUID(statement, 3),
        modelId: String(cString: sqlite3_column_text(statement, 4)),
        temperature: sqlite3_column_double(statement, 5),
        maxTokens: Int(sqlite3_column_int64(statement, 6)),
        isWebSearchEnabled: sqlite3_column_int(statement, 7) != 0,
        reasoningEffort: ReasoningEffort(rawValue: optionalString(statement, 10) ?? "automatic")
          ?? .automatic,
        quickTemplates: templates,
        contextMessageCount: Int(sqlite3_column_int64(statement, 9))
      )
    }
  }

  func saveSearchSettings(_ settings: SearchSettings) throws {
    let data = try JSONEncoder().encode(settings)
    try setSetting(key: "search", value: String(data: data, encoding: .utf8) ?? "{}")
  }

  func loadSearchSettings() throws -> SearchSettings? {
    guard let value = try getSetting(key: "search") else { return nil }
    return try JSONDecoder().decode(SearchSettings.self, from: Data(value.utf8))
  }

  func saveAppPreferences(_ preferences: AppPreferences) throws {
    let data = try JSONEncoder().encode(preferences)
    try setSetting(key: "preferences", value: String(data: data, encoding: .utf8) ?? "{}")
  }

  func loadAppPreferences() throws -> AppPreferences? {
    guard let value = try getSetting(key: "preferences") else { return nil }
    return try JSONDecoder().decode(AppPreferences.self, from: Data(value.utf8))
  }

  func appendMessage(_ message: ChatMessage) throws {
    let citationsData = try JSONEncoder().encode(message.citations)
    let usageData = try message.usage.map { try JSONEncoder().encode($0) }
    let attachmentsData = try JSONEncoder().encode(message.attachments)
    try execute(
      """
      INSERT INTO messages (
        id, conversation_id, role, content, reasoning_content,
        citations_json, status, usage_json, attachments_json,
        first_token_latency_ms, tokens_per_second, created_at, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        message.id.uuidString,
        message.conversationId.uuidString,
        message.role.rawValue,
        message.content,
        message.reasoningContent,
        String(data: citationsData, encoding: .utf8) ?? "[]",
        message.status.rawValue,
        usageData.flatMap { String(data: $0, encoding: .utf8) },
        String(data: attachmentsData, encoding: .utf8) ?? "[]",
        message.firstTokenLatencyMS,
        message.tokensPerSecond,
        message.createdAt.timeIntervalSince1970,
        message.updatedAt.timeIntervalSince1970,
      ]
    )
  }

  func updateMessage(_ message: ChatMessage) throws {
    let citationsData = try JSONEncoder().encode(message.citations)
    let usageData = try message.usage.map { try JSONEncoder().encode($0) }
    let attachmentsData = try JSONEncoder().encode(message.attachments)
    try execute(
      """
      UPDATE messages
      SET content = ?,
          reasoning_content = ?,
          citations_json = ?,
          status = ?,
          usage_json = ?,
          attachments_json = ?,
          first_token_latency_ms = ?,
          tokens_per_second = ?,
          updated_at = ?
      WHERE id = ?
      """,
      [
        message.content,
        message.reasoningContent,
        String(data: citationsData, encoding: .utf8) ?? "[]",
        message.status.rawValue,
        usageData.flatMap { String(data: $0, encoding: .utf8) },
        String(data: attachmentsData, encoding: .utf8) ?? "[]",
        message.firstTokenLatencyMS,
        message.tokensPerSecond,
        message.updatedAt.timeIntervalSince1970,
        message.id.uuidString,
      ]
    )
  }

  func listMessages(conversationId: UUID) throws -> [ChatMessage] {
    try query(
      """
      SELECT id, conversation_id, role, content, reasoning_content,
             citations_json, status, usage_json, attachments_json,
             first_token_latency_ms, tokens_per_second, created_at, updated_at
      FROM messages
      WHERE conversation_id = ?
      ORDER BY created_at ASC
      """,
      [conversationId.uuidString]
    ) { statement in
      let citationsText = String(cString: sqlite3_column_text(statement, 5))
      let usageText = optionalString(statement, 7)
      let attachmentsText = optionalString(statement, 8) ?? "[]"
      return ChatMessage(
        id: UUID(uuidString: String(cString: sqlite3_column_text(statement, 0))) ?? UUID(),
        conversationId: UUID(uuidString: String(cString: sqlite3_column_text(statement, 1)))
          ?? conversationId,
        role: ChatRole(rawValue: String(cString: sqlite3_column_text(statement, 2))) ?? .user,
        content: String(cString: sqlite3_column_text(statement, 3)),
        reasoningContent: optionalString(statement, 4) ?? "",
        citations: (try? JSONDecoder().decode([Citation].self, from: Data(citationsText.utf8)))
          ?? [],
        attachments: (try? JSONDecoder().decode(
          [MessageImage].self, from: Data(attachmentsText.utf8))) ?? [],
        status: MessageStatus(rawValue: String(cString: sqlite3_column_text(statement, 6)))
          ?? .success,
        usage: usageText.flatMap {
          try? JSONDecoder().decode(TokenUsage.self, from: Data($0.utf8))
        },
        firstTokenLatencyMS: optionalInt(statement, 9),
        tokensPerSecond: optionalInt(statement, 10),
        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11)),
        updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 12))
      )
    }
  }

  private func migrate() throws {
    try execute(
      """
      CREATE TABLE IF NOT EXISTS conversations (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        assistant_id TEXT,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
      )
      """
    )
    try execute(
      """
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        reasoning_content TEXT NOT NULL DEFAULT '',
        citations_json TEXT NOT NULL,
        status TEXT NOT NULL,
        usage_json TEXT,
        created_at REAL NOT NULL,
        updated_at REAL NOT NULL
      )
      """
    )
    try addColumnIfNeeded(
      table: "messages", column: "reasoning_content", definition: "TEXT NOT NULL DEFAULT ''")
    try addColumnIfNeeded(
      table: "messages", column: "first_token_latency_ms", definition: "INTEGER")
    try addColumnIfNeeded(table: "messages", column: "tokens_per_second", definition: "INTEGER")
    try execute(
      """
      CREATE TABLE IF NOT EXISTS providers (
        id TEXT PRIMARY KEY,
        provider_type TEXT,
        kind TEXT NOT NULL,
        name TEXT NOT NULL,
        base_url TEXT NOT NULL,
        api_key_name TEXT NOT NULL DEFAULT '',
        api_key TEXT NOT NULL DEFAULT '',
        models_json TEXT NOT NULL,
        vision_models_json TEXT NOT NULL DEFAULT '[]',
        default_model TEXT NOT NULL,
        is_enabled INTEGER NOT NULL
      )
      """
    )
    try addColumnIfNeeded(table: "providers", column: "provider_type", definition: "TEXT")
    try addColumnIfNeeded(
      table: "providers", column: "api_key", definition: "TEXT NOT NULL DEFAULT ''")
    try addColumnIfNeeded(
      table: "providers", column: "vision_models_json", definition: "TEXT NOT NULL DEFAULT '[]'")
    try execute(
      """
      CREATE TABLE IF NOT EXISTS assistants (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        system_prompt TEXT NOT NULL,
        provider_id TEXT,
        model_id TEXT NOT NULL,
        temperature REAL NOT NULL,
        max_tokens INTEGER NOT NULL,
        is_web_search_enabled INTEGER NOT NULL,
        templates_json TEXT NOT NULL
      )
      """
    )
    try addColumnIfNeeded(
      table: "assistants", column: "context_message_count",
      definition: "INTEGER NOT NULL DEFAULT 20")
    try addColumnIfNeeded(
      table: "assistants", column: "reasoning_effort",
      definition: "TEXT NOT NULL DEFAULT 'automatic'")
    try addColumnIfNeeded(
      table: "messages", column: "attachments_json", definition: "TEXT NOT NULL DEFAULT '[]'")
    try execute(
      """
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
      """
    )
  }

  private func setSetting(key: String, value: String) throws {
    try execute(
      """
      INSERT INTO app_settings (key, value)
      VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      """,
      [key, value]
    )
  }

  private func getSetting(key: String) throws -> String? {
    try query("SELECT value FROM app_settings WHERE key = ?", [key]) { statement in
      optionalString(statement, 0)
    }.first ?? nil
  }

  private func addColumnIfNeeded(table: String, column: String, definition: String) throws {
    let rows = try query("PRAGMA table_info(\(table))") { statement in
      String(cString: sqlite3_column_text(statement, 1))
    }
    guard !rows.contains(column) else { return }
    try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
  }

  private func execute(_ sql: String, _ bindings: [Any?] = []) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw SQLiteStoreError.prepare(message: lastErrorMessage)
    }
    defer { sqlite3_finalize(statement) }

    bind(bindings, to: statement)

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw SQLiteStoreError.execute(message: lastErrorMessage)
    }
  }

  private func query<T>(_ sql: String, _ bindings: [Any?] = [], map: (OpaquePointer?) throws -> T)
    throws -> [T]
  {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw SQLiteStoreError.prepare(message: lastErrorMessage)
    }
    defer { sqlite3_finalize(statement) }

    bind(bindings, to: statement)

    var rows: [T] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      rows.append(try map(statement))
    }
    return rows
  }

  private func bind(_ bindings: [Any?], to statement: OpaquePointer?) {
    for (index, value) in bindings.enumerated() {
      let sqliteIndex = Int32(index + 1)
      switch value {
      case nil:
        sqlite3_bind_null(statement, sqliteIndex)
      case let value as String:
        sqlite3_bind_text(statement, sqliteIndex, value, -1, SQLITE_TRANSIENT)
      case let value as Double:
        sqlite3_bind_double(statement, sqliteIndex, value)
      case let value as Int:
        sqlite3_bind_int64(statement, sqliteIndex, sqlite3_int64(value))
      case let value as Bool:
        sqlite3_bind_int(statement, sqliteIndex, value ? 1 : 0)
      default:
        sqlite3_bind_text(statement, sqliteIndex, String(describing: value!), -1, SQLITE_TRANSIENT)
      }
    }
  }

  private var lastErrorMessage: String {
    guard let db, let message = sqlite3_errmsg(db) else { return "unknown SQLite error" }
    return String(cString: message)
  }
}

private func optionalString(_ statement: OpaquePointer?, _ index: Int32) -> String? {
  guard sqlite3_column_type(statement, index) != SQLITE_NULL,
    let text = sqlite3_column_text(statement, index)
  else {
    return nil
  }
  return String(cString: text)
}

private func optionalInt(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
  guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
    return nil
  }
  return Int(sqlite3_column_int64(statement, index))
}

private func optionalUUID(_ statement: OpaquePointer?, _ index: Int32) -> UUID? {
  optionalString(statement, index).flatMap(UUID.init(uuidString:))
}

private func inferProviderType(name: String, kind: ProviderKind) -> ProviderCatalogType {
  let normalized = name.lowercased()
  if normalized.contains("new api") || normalized.contains("newapi") {
    return .newAPI
  }
  if normalized.contains("anthropic") || kind == .anthropicMessages {
    return .anthropic
  }
  if normalized.contains("response") || kind == .openAIResponses {
    return .openAIResponse
  }
  return .openAI
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteStoreError: Error, LocalizedError {
  case open(message: String)
  case prepare(message: String)
  case execute(message: String)

  var errorDescription: String? {
    switch self {
    case .open(let message): "Could not open SQLite database: \(message)"
    case .prepare(let message): "Could not prepare SQLite statement: \(message)"
    case .execute(let message): "Could not execute SQLite statement: \(message)"
    }
  }
}
