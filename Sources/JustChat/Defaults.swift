import Foundation

enum Defaults {
    static func providers() -> [ModelProvider] {
        [
            ModelProvider(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000101")!,
                providerType: .openAIResponse,
                kind: .openAIResponses,
                name: "OpenAI",
                baseURL: URL(string: "https://api.openai.com/v1")!,
                models: ["gpt-5.4", "gpt-5.4-mini", "gpt-5.3"],
                defaultModel: "gpt-5.4"
            ),
            ModelProvider(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000102")!,
                providerType: .newAPI,
                kind: .openAIChatCompletions,
                name: "New API",
                baseURL: URL(string: "https://newapi.example.com/v1")!,
                models: ["gpt-5.4-mini", "gpt-5.3"],
                defaultModel: "gpt-5.4-mini"
            ),
            ModelProvider(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000103")!,
                providerType: .anthropic,
                kind: .anthropicMessages,
                name: "Anthropic",
                baseURL: URL(string: "https://api.anthropic.com/v1")!,
                models: ["claude-opus-4-5", "claude-sonnet-4-5"],
                defaultModel: "claude-sonnet-4-5"
            )
        ]
    }

    static func assistants(primaryProviderId: UUID) -> [AssistantProfile] {
        [
            AssistantProfile(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000201")!,
                name: "默认助手",
                systemPrompt: "你是一个清晰、直接、注重事实的桌面 AI 助手。",
                providerId: primaryProviderId,
                modelId: "gpt-5.4",
                temperature: 0.7,
                maxTokens: 4096,
                isWebSearchEnabled: true,
                quickTemplates: [
                    PromptTemplate(id: UUID(), title: "翻译", prompt: "翻译为简体中文，保持原意："),
                    PromptTemplate(id: UUID(), title: "总结", prompt: "用要点总结这段内容："),
                    PromptTemplate(id: UUID(), title: "解释", prompt: "解释这段内容的重点和背景：")
                ]
            ),
            AssistantProfile(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000202")!,
                name: "翻译成英文 - English",
                systemPrompt: "你是一个专业翻译助手。将用户输入翻译为自然、准确、简洁的英文，保留专有名词、代码、命令和 Markdown 结构。",
                providerId: primaryProviderId,
                modelId: "gpt-5.4",
                temperature: 0.3,
                maxTokens: 4096,
                isWebSearchEnabled: false,
                quickTemplates: [
                    PromptTemplate(id: UUID(), title: "翻译", prompt: "Translate to natural English:"),
                    PromptTemplate(id: UUID(), title: "润色", prompt: "Polish this English while keeping the meaning:")
                ]
            ),
            AssistantProfile(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000203")!,
                name: "翻译成中文 - Chinese",
                systemPrompt: "你是一个专业翻译助手。将用户输入翻译为流畅、准确的简体中文，保留术语、代码、链接和 Markdown 结构。",
                providerId: primaryProviderId,
                modelId: "gpt-5.4",
                temperature: 0.3,
                maxTokens: 4096,
                isWebSearchEnabled: false,
                quickTemplates: [
                    PromptTemplate(id: UUID(), title: "翻译", prompt: "翻译为简体中文："),
                    PromptTemplate(id: UUID(), title: "解释", prompt: "翻译并解释关键术语：")
                ]
            ),
            AssistantProfile(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000204")!,
                name: "周报助手",
                systemPrompt: "你帮助用户把零散记录整理成结构清晰的周报，突出成果、风险、下周计划和需要协作的事项。",
                providerId: primaryProviderId,
                modelId: "gpt-5.4",
                temperature: 0.5,
                maxTokens: 4096,
                isWebSearchEnabled: false,
                quickTemplates: [
                    PromptTemplate(id: UUID(), title: "周报", prompt: "把以下内容整理成周报："),
                    PromptTemplate(id: UUID(), title: "计划", prompt: "根据这些记录提炼下周计划：")
                ]
            )
        ]
    }
}
