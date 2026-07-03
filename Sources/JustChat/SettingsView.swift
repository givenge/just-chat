import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            SettingsNavigation()
                .frame(width: 280)

            Divider()

            if appState.selectedSettingsPane == .providers {
                ProviderListColumn()
                    .frame(width: 300)
                Divider()
            }

            SettingsDetailColumn()
        }
        .background(Color.justWindowBackground)
    }
}

private struct SettingsNavigation: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    appState.rootSection = .home
                } label: {
                    Label("返回", systemImage: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .hoverSurface(radius: Radius.sm, opacity: 0.5)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    settingsButton(.providers, icon: "cloud")
                    settingsButton(.defaultModel, icon: "shippingbox")

                    Divider().padding(.vertical, 4)

                    settingsButton(.general, icon: "slider.horizontal.3")
                    settingsButton(.display, icon: "display")
                    settingsButton(.data, icon: "externaldrive")

                    Divider().padding(.vertical, 4)

                    settingsButton(.search, icon: "magnifyingglass")
                    settingsButton(.quickAssistant, icon: "rectangle.on.rectangle")
                    settingsButton(.selectionAssistant, icon: "text.viewfinder")
                    settingsButton(.hotKeys, icon: "command")

                    Divider().padding(.vertical, 4)

                    settingsButton(.about, icon: "info.circle")
                }
                .padding(16)
            }
        }
        .background(Color.justSidebarBackground)
    }

    private func settingsButton(_ pane: SettingsPane, icon: String) -> some View {
        let isActive = appState.selectedSettingsPane == pane
        return Button {
            appState.selectedSettingsPane = pane
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 24)
                    .foregroundStyle(isActive ? Color.justAccent : .secondary)
                Text(pane.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isActive ? Color.justControlBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Color.justBorderSoft, lineWidth: isActive ? 1 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverSurface(radius: Radius.md, opacity: 0.5)
    }
}

private struct ProviderListColumn: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var isAddingProvider = false

    var filteredProviders: [ModelProvider] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return appState.providers }
        return appState.providers.filter { provider in
            provider.name.localizedCaseInsensitiveContains(text)
                || provider.providerType.displayName.localizedCaseInsensitiveContains(text)
                || provider.kind.displayName.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索模型平台...", text: $searchText)
                    .textFieldStyle(.plain)
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Color.justBorderSoft, lineWidth: 1)
            )
            .padding(.horizontal, 14)
            .padding(.top, 14)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredProviders) { provider in
                        ProviderListRow(provider: provider)
                    }
                }
                .padding(.horizontal, 14)
            }

            Button {
                isAddingProvider = true
            } label: {
                Label("添加", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .stroke(Color.justBorderSoft, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .hoverSurface(radius: Radius.sm, opacity: 0.6)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(Color.justSidebarBackground)
        .sheet(isPresented: $isAddingProvider) {
            AddProviderSheet()
                .environmentObject(appState)
        }
    }
}

private struct ProviderListRow: View {
    @EnvironmentObject private var appState: AppState
    var provider: ModelProvider

    private var isSelected: Bool { appState.selectedProviderId == provider.id }

    var body: some View {
        Button {
            appState.selectedProviderId = provider.id
        } label: {
            HStack(spacing: 12) {
                ProviderAvatar(provider: provider)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(provider.kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(provider.providerType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if provider.isEnabled {
                        Text("ON")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.justSuccess)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Color.justSuccess.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? Color.justControlBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Color.justBorderSoft, lineWidth: isSelected ? 1 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverSurface(radius: Radius.md, opacity: 0.5)
    }
}

private struct AddProviderSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var providerType: ProviderCatalogType = .openAI

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("添加提供商")
                .font(.system(size: 24, weight: .bold))

            Divider()

            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.justControlBackground)
                        .overlay(Circle().stroke(Color.justBorderSoft, lineWidth: 1))
                    Text(String((effectiveName.first ?? "P")))
                        .font(.system(size: 34, weight: .bold))
                }
                .frame(width: 94, height: 94)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("提供商名称")
                    .font(.system(size: 17, weight: .semibold))
                TextField("例如 OpenAI", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("提供商类型")
                    .font(.system(size: 17, weight: .semibold))
                Picker("提供商类型", selection: $providerType) {
                    ForEach(ProviderCatalogType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Color.justControlBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(Color.justBorderSoft, lineWidth: 1)
                )

                Text("接口类型：\(providerType.defaultKind.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .focusable(false)
                Button("添加") {
                    appState.addProvider(type: providerType, name: effectiveName)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.justAccent)
                .focusable(false)
            }
        }
        .padding(28)
        .frame(width: 520, height: 560)
        .background(Color.justWindowBackground)
    }

    private var effectiveName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? providerType.displayName : trimmed
    }
}

private struct SettingsDetailColumn: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            switch appState.selectedSettingsPane {
            case .providers:
                ProviderDetailPane()
            case .defaultModel:
                DefaultModelPane()
            case .general:
                GeneralSettingsPane()
            case .display:
                DisplaySettingsPane()
            case .data:
                PlaceholderPane(title: "数据设置", subtitle: "本地数据存储在 Application Support/JustChat/just-chat.sqlite。")
            case .search:
                SearchSettingsPane()
            case .quickAssistant:
                QuickAssistantSettingsPane()
            case .selectionAssistant:
                SelectionAssistantSettingsPane()
            case .hotKeys:
                HotKeySettingsPane()
            case .about:
                PlaceholderPane(title: "关于我们", subtitle: "Just Chat 是基于 Cherry Studio 核心工作流精简实现的原生 macOS AI 客户端。")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.justWindowBackground)
    }
}

private struct ProviderDetailPane: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRefreshingModels = false
    @State private var availableModels: [String] = []
    @State private var modelBrowserPresented = false
    @State private var showsAPIKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(provider.name)
                    .font(.system(size: 20, weight: .bold))
                Image(systemName: "hexagon")
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("启用", isOn: providerEnabledBinding)
                    .labelsHidden()
                    .tint(Color.justAccent)
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingTitle("提供商", icon: "building.2")
                    LabeledContent("提供商类型", value: provider.providerType.displayName)
                    LabeledContent("接口类型", value: provider.kind.displayName)
                    Text("提供商类型用于展示和默认配置；接口类型决定实际请求使用 Chat Completions、Responses 或 Anthropic Messages。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingTitle("API 密钥", icon: "key")
                    HStack {
                        APIKeyField("API Key", text: apiKeyBinding, isRevealed: $showsAPIKey)
                        Button("检测") {
                            isRefreshingModels = true
                            Task {
                                _ = await appState.fetchAvailableModels(for: provider.id)
                                isRefreshingModels = false
                            }
                        }
                        .disabled(isRefreshingModels)
                        .focusable(false)
                    }
                    Text("API Key 直接保存在本地配置中，不再访问系统钥匙串。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingTitle("API 地址", icon: "link")
                    TextField("API 地址", text: baseURLBinding)
                        .textFieldStyle(.roundedBorder)
                    Text("预览：\(provider.baseURL.absoluteString)/\(provider.kind == .openAIChatCompletions ? "chat/completions" : provider.kind == .openAIResponses ? "responses" : "messages")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        settingTitle("模型", icon: "cube")
                        Spacer()
                        Button {
                            isRefreshingModels = true
                            Task {
                                let models = await appState.fetchAvailableModels(for: provider.id)
                                availableModels = models
                                modelBrowserPresented = !models.isEmpty
                                isRefreshingModels = false
                            }
                        } label: {
                            if isRefreshingModels {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Label("获取模型列表", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(isRefreshingModels)
                        .focusable(false)
                        Button {
                            appendModel()
                        } label: {
                            Label("添加模型", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .focusable(false)
                    }

                    ForEach(modelIndices, id: \.self) { index in
                        HStack {
                            TextField("模型 ID", text: modelBinding(index))
                                .textFieldStyle(.roundedBorder)
                            Button {
                                toggleVisionModel(at: index)
                            } label: {
                                Image(systemName: modelSupportsVision(at: index) ? "eye.fill" : "eye")
                                    .foregroundStyle(modelSupportsVision(at: index) ? Color.justAccent : Color.secondary)
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .help(modelSupportsVision(at: index) ? "关闭视觉能力" : "开启视觉能力")
                            Button {
                                removeModel(at: index)
                            } label: {
                                Image(systemName: "minus")
                                    .foregroundStyle(Color.justDanger)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .disabled(provider.models.count <= 1)
                        }
                    }
                }
            }

            HStack {
                Button("保存设置") {
                    appState.persistConfiguration()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.justAccent)
                .focusable(false)

                Button("删除模型服务", role: .destructive) {
                    appState.deleteSelectedProvider()
                }
                .disabled(appState.providers.count <= 1)
                .focusable(false)
            }
        }
        .padding(28)
        .frame(maxWidth: 760, alignment: .leading)
        .sheet(isPresented: $modelBrowserPresented) {
            ProviderModelBrowserSheet(providerId: provider.id, remoteModels: availableModels)
                .environmentObject(appState)
        }
    }

    private var provider: ModelProvider {
        appState.selectedProvider
    }

    private var providerIndex: Int? {
        appState.providers.firstIndex(where: { $0.id == appState.selectedProviderId })
    }

    private var modelIndices: [Int] {
        guard let providerIndex else { return [] }
        return Array(appState.providers[providerIndex].models.indices)
    }

    private var providerEnabledBinding: Binding<Bool> {
        Binding(
            get: { provider.isEnabled },
            set: { value in
                guard let providerIndex else { return }
                appState.providers[providerIndex].isEnabled = value
            }
        )
    }

    private var baseURLBinding: Binding<String> {
        Binding(
            get: { provider.baseURL.absoluteString },
            set: { value in
                guard let providerIndex, let url = URL(string: value) else { return }
                appState.providers[providerIndex].baseURL = url
            }
        )
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { provider.apiKey },
            set: { value in
                guard let providerIndex else { return }
                appState.providers[providerIndex].apiKey = value
            }
        )
    }

    private func modelBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let providerIndex,
                      appState.providers[providerIndex].models.indices.contains(index)
                else { return "" }
                return appState.providers[providerIndex].models[index]
            },
            set: { value in
                guard let providerIndex,
                      appState.providers[providerIndex].models.indices.contains(index)
                else { return }
                let oldValue = appState.providers[providerIndex].models[index]
                let wasVisionModel = appState.providers[providerIndex].visionModels.remove(oldValue) != nil
                appState.providers[providerIndex].models[index] = value
                if wasVisionModel, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appState.providers[providerIndex].visionModels.insert(value)
                }
                if appState.providers[providerIndex].defaultModel == oldValue {
                    appState.providers[providerIndex].defaultModel = value
                }
            }
        )
    }

    private func appendModel() {
        guard let providerIndex else { return }
        appState.providers[providerIndex].models.append("new-model")
    }

    private func removeModel(at index: Int) {
        guard let providerIndex,
              appState.providers[providerIndex].models.indices.contains(index),
              appState.providers[providerIndex].models.count > 1
        else { return }
        let removed = appState.providers[providerIndex].models.remove(at: index)
        appState.providers[providerIndex].visionModels.remove(removed)
        if appState.providers[providerIndex].defaultModel == removed {
            appState.providers[providerIndex].defaultModel = appState.providers[providerIndex].models[0]
        }
    }

    private func modelSupportsVision(at index: Int) -> Bool {
        guard let providerIndex,
              appState.providers[providerIndex].models.indices.contains(index)
        else { return false }
        return appState.providers[providerIndex].visionModels.contains(appState.providers[providerIndex].models[index])
    }

    private func toggleVisionModel(at index: Int) {
        guard let providerIndex,
              appState.providers[providerIndex].models.indices.contains(index)
        else { return }
        let model = appState.providers[providerIndex].models[index]
        if appState.providers[providerIndex].visionModels.contains(model) {
            appState.providers[providerIndex].visionModels.remove(model)
        } else {
            appState.providers[providerIndex].visionModels.insert(model)
        }
    }

}

private struct ProviderModelBrowserSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var providerId: UUID
    var remoteModels: [String]

    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("\(provider?.name ?? "模型服务") 模型")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverSurface(radius: Radius.sm)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索模型 ID 或名称", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Color.justInputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(Color.justBorderSoft, lineWidth: 1)
            )

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(groupedModels, id: \.name) { group in
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Text(group.name)
                                    .font(.system(size: 15, weight: .bold))
                                Text("\(group.models.count)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.justSuccess)
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                                    .background(Color.justSuccess.opacity(0.12))
                                    .clipShape(Capsule())
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(Color.justControlBackground.opacity(0.7))

                            ForEach(group.models, id: \.self) { model in
                                HStack(spacing: 12) {
                                    Text(model)
                                        .font(.system(size: 15, weight: .semibold))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button {
                                        toggleModel(model)
                                    } label: {
                                        Image(systemName: isAdded(model) ? "minus" : "plus")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(isAdded(model) ? Color.justDanger : Color.primary)
                                            .frame(width: 28, height: 28)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .hoverSurface(radius: Radius.sm)
                                    .disabled(isAdded(model) && (provider?.models.count ?? 0) <= 1)
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 46)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                        .fill(isAdded(model) ? Color.justSuccess.opacity(0.08) : Color.clear)
                                )
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(Color.justControlBackground.opacity(0.35))
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Text("只会添加右侧点过加号的模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("完成") {
                    appState.persistConfiguration()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.justAccent)
                .focusable(false)
            }
        }
        .padding(24)
        .frame(width: 720, height: 620)
        .background(Color.justWindowBackground)
    }

    private var providerIndex: Int? {
        appState.providers.firstIndex(where: { $0.id == providerId })
    }

    private var provider: ModelProvider? {
        guard let providerIndex else { return nil }
        return appState.providers[providerIndex]
    }

    private var filteredModels: [String] {
        let uniqueModels = Array(Set(remoteModels)).sorted()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return uniqueModels }
        return uniqueModels.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var groupedModels: [(name: String, models: [String])] {
        Dictionary(grouping: filteredModels, by: groupName(for:))
            .map { (name: $0.key, models: $0.value.sorted()) }
            .sorted { lhs, rhs in
                if lhs.name == "其他" { return false }
                if rhs.name == "其他" { return true }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func groupName(for model: String) -> String {
        let prefix = model.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
        return prefix.isEmpty || prefix == model ? "其他" : prefix
    }

    private func isAdded(_ model: String) -> Bool {
        provider?.models.contains(model) == true
    }

    private func toggleModel(_ model: String) {
        if isAdded(model) {
            removeModel(model)
        } else {
            addModel(model)
        }
    }

    private func addModel(_ model: String) {
        guard let providerIndex,
              !appState.providers[providerIndex].models.contains(model)
        else { return }
        appState.providers[providerIndex].models.append(model)
        if appState.providers[providerIndex].defaultModel.isEmpty {
            appState.providers[providerIndex].defaultModel = model
        }
    }

    private func removeModel(_ model: String) {
        guard let providerIndex,
              appState.providers[providerIndex].models.count > 1
        else { return }
        appState.providers[providerIndex].models.removeAll { $0 == model }
        appState.providers[providerIndex].visionModels.remove(model)
        if appState.providers[providerIndex].defaultModel == model {
            appState.providers[providerIndex].defaultModel = appState.providers[providerIndex].models.first ?? ""
        }
    }
}

private struct DefaultModelPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("默认模型")
                    .font(.system(size: 24, weight: .bold))
                Text("为常用任务指定模型和思考等级。默认表示不发送思考参数。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            SettingsCard {
                VStack(spacing: 0) {
                    modelRow(
                        title: "默认助手模型",
                        icon: "message",
                        description: "创建新助手时使用，也作为助手模型缺失时的回退。",
                        providerId: defaultAssistantProviderBinding,
                        modelId: defaultAssistantModelBinding,
                        reasoningEffort: defaultAssistantReasoningBinding
                    )
                    Divider()
                    modelRow(
                        title: "快速模型",
                        icon: "hare",
                        description: "快捷助手与轻量任务使用的模型。",
                        providerId: quickProviderBinding,
                        modelId: quickModelBinding,
                        reasoningEffort: quickReasoningBinding
                    )
                    Divider()
                    modelRow(
                        title: "翻译模型",
                        icon: "character.book.closed",
                        description: "划词助手执行翻译动作时使用的模型。",
                        providerId: translationProviderBinding,
                        modelId: translationModelBinding,
                        reasoningEffort: translationReasoningBinding
                    )
                }
            }

            HStack {
                Spacer()
                Button("保存默认模型设置") {
                    appState.persistConfiguration()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.justAccent)
                .focusable(false)
            }
        }
        .padding(28)
        .frame(maxWidth: 1040, alignment: .leading)
    }

    private var defaultAssistantProviderBinding: Binding<UUID> {
        Binding(
            get: { appState.defaultAssistantModelSelection.provider.id },
            set: { providerId in
                appState.preferences.defaultAssistantProviderId = providerId
                appState.preferences.defaultAssistantModelId = initialModel(for: providerId, currentModel: appState.preferences.defaultAssistantModelId)
            }
        )
    }

    private var defaultAssistantModelBinding: Binding<String> {
        Binding(
            get: { appState.defaultAssistantModelSelection.modelId },
            set: { value in
                appState.preferences.defaultAssistantModelId = value
            }
        )
    }

    private var defaultAssistantReasoningBinding: Binding<ReasoningEffort> {
        Binding(
            get: { appState.preferences.defaultAssistantReasoningEffort },
            set: { appState.preferences.defaultAssistantReasoningEffort = $0 }
        )
    }

    private var quickProviderBinding: Binding<UUID> {
        Binding(
            get: { appState.quickModelSelection.provider.id },
            set: { providerId in
                appState.preferences.quickModelProviderId = providerId
                appState.preferences.quickModelId = initialModel(for: providerId, currentModel: appState.preferences.quickModelId)
            }
        )
    }

    private var quickModelBinding: Binding<String> {
        Binding(
            get: { appState.quickModelSelection.modelId },
            set: { value in
                appState.preferences.quickModelId = value
            }
        )
    }

    private var quickReasoningBinding: Binding<ReasoningEffort> {
        Binding(
            get: { appState.preferences.quickReasoningEffort },
            set: { appState.preferences.quickReasoningEffort = $0 }
        )
    }

    private var translationProviderBinding: Binding<UUID> {
        Binding(
            get: { appState.translationModelSelection.provider.id },
            set: { providerId in
                appState.preferences.translationModelProviderId = providerId
                appState.preferences.translationModelId = initialModel(for: providerId, currentModel: appState.preferences.translationModelId)
            }
        )
    }

    private var translationModelBinding: Binding<String> {
        Binding(
            get: { appState.translationModelSelection.modelId },
            set: { value in
                appState.preferences.translationModelId = value
            }
        )
    }

    private var translationReasoningBinding: Binding<ReasoningEffort> {
        Binding(
            get: { appState.preferences.translationReasoningEffort },
            set: { appState.preferences.translationReasoningEffort = $0 }
        )
    }

    private func modelRow(
        title: String,
        icon: String,
        description: String,
        providerId: Binding<UUID>,
        modelId: Binding<String>,
        reasoningEffort: Binding<ReasoningEffort>
    ) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.justAccent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ModelSelectionControl(
                providerId: providerId,
                modelId: modelId,
                reasoningEffort: reasoningEffort
            )
            .frame(width: 600)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func initialModel(for providerId: UUID, currentModel: String) -> String {
        guard let provider = appState.providers.first(where: { $0.id == providerId }) else {
            return currentModel
        }
        if provider.models.contains(currentModel) {
            return currentModel
        }
        return provider.defaultModel.isEmpty ? (provider.models.first ?? "") : provider.defaultModel
    }
}

private struct ModelSelectionControl: View {
    @EnvironmentObject private var appState: AppState
    @Binding var providerId: UUID
    @Binding var modelId: String
    @Binding var reasoningEffort: ReasoningEffort

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            controlColumn("模型服务", width: 150) {
                Picker("模型服务", selection: providerSelection) {
                    ForEach(appState.providers) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                }
                .labelsHidden()
            }

            controlColumn("模型", width: 260) {
                Picker("模型", selection: $modelId) {
                    ForEach(provider.models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .disabled(provider.models.isEmpty)
            }

            controlColumn("思考等级", width: 130) {
                Picker("思考等级", selection: $reasoningEffort) {
                    ForEach(ReasoningEffort.allCases) { effort in
                        Text(effort.displayName).tag(effort)
                    }
                }
                .labelsHidden()
            }
        }
        .pickerStyle(.menu)
    }

    private var provider: ModelProvider {
        appState.providers.first(where: { $0.id == providerId }) ?? appState.providers.first ?? appState.activeProvider
    }

    private var providerSelection: Binding<UUID> {
        Binding(
            get: { providerId },
            set: { newProviderId in
                providerId = newProviderId
                guard let selectedProvider = appState.providers.first(where: { $0.id == newProviderId }) else { return }
                if !selectedProvider.models.contains(modelId) {
                    modelId = selectedProvider.defaultModel.isEmpty ? (selectedProvider.models.first ?? "") : selectedProvider.defaultModel
                }
            }
        )
    }

    private func controlColumn<Content: View>(
        _ title: String,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(width: width, alignment: .leading)
    }
}

private struct GeneralSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingTitle("对话区", icon: "textformat.size")
                    HStack {
                        Text("字体大小")
                        Slider(value: $appState.preferences.chatFontSize, in: 12...20, step: 1)
                            .tint(Color.justAccent)
                        Text("\(Int(appState.preferences.chatFontSize))")
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                    }
                    HStack {
                        Text("侧栏宽度")
                        Slider(value: $appState.preferences.homeSidebarWidth, in: 240...460, step: 1)
                            .tint(Color.justAccent)
                        Text("\(Int(appState.preferences.homeSidebarWidth))")
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            Button("保存常规设置") {
                appState.persistConfiguration()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.justAccent)
            .focusable(false)
        }
        .padding(28)
        .frame(maxWidth: 760, alignment: .leading)
    }
}

private struct SearchSettingsPane: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsTavilyKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingTitle("Tavily", icon: "magnifyingglass")
                    LabeledContent("搜索端点", value: "https://api.tavily.com/search")
                    APIKeyField("Tavily API Key", text: $appState.searchSettings.tavilyAPIKey, isRevealed: $showsTavilyKey)
                    Stepper("默认结果数：\(appState.searchSettings.tavilyMaxResults)", value: $appState.searchSettings.tavilyMaxResults, in: 1...10)
                    Text("Tavily API Key 直接保存在本地配置中。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingTitle("模型原生搜索", icon: "globe")
                    Toggle("OpenAI Responses 使用 web_search 工具", isOn: $appState.searchSettings.useOpenAIResponsesNativeSearch)
                        .tint(Color.justAccent)
                    Text("Chat Completions 和 Anthropic Messages 使用 Tavily 结果注入上下文。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("保存搜索设置") {
                appState.persistConfiguration()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.justAccent)
            .focusable(false)
        }
        .padding(28)
        .frame(maxWidth: 760, alignment: .leading)
    }
}

private struct APIKeyField: View {
    var placeholder: String
    @Binding var text: String
    @Binding var isRevealed: Bool

    init(_ placeholder: String, text: Binding<String>, isRevealed: Binding<Bool>) {
        self.placeholder = placeholder
        self._text = text
        self._isRevealed = isRevealed
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .hoverSurface(radius: Radius.sm)
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.justInputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
        )
    }
}

private struct QuickAssistantSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                HStack {
                    settingTitle("快捷助手", icon: "rectangle.on.rectangle")
                    Spacer()
                    Toggle("启用", isOn: $appState.preferences.quickAssistantEnabled)
                        .labelsHidden()
                        .tint(Color.justAccent)
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingTitle("窗口", icon: "macwindow")
                    Text("快捷助手不再读取剪贴板，内容仅来自当前输入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("呼出快捷键", value: appState.preferences.quickAssistantHotKey)
                    Button("测试打开快捷助手") {
                        appState.showQuickAssistant()
                    }
                    .focusable(false)
                }
            }

            Button("保存快捷助手设置") {
                appState.persistConfiguration()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.justAccent)
            .focusable(false)
        }
        .padding(28)
        .frame(maxWidth: 760, alignment: .leading)
    }
}

private struct SelectionAssistantSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                HStack {
                    VStack(alignment: .leading, spacing: 10) {
                        settingTitle("划词助手", icon: "text.viewfinder")
                        Text("使用快捷键呼出工具栏，读取当前屏幕选中的文本。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("启用", isOn: $appState.preferences.selectionAssistantEnabled)
                        .labelsHidden()
                        .tint(Color.justAccent)
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    settingTitle("工具栏", icon: "rectangle.compress.vertical")
                    Picker("取词方式", selection: $appState.preferences.selectionTriggerMode) {
                        ForEach(SelectionTriggerMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("紧凑模式", isOn: $appState.preferences.selectionCompactMode)
                        .tint(Color.justAccent)
                    LabeledContent("呼出快捷键", value: appState.preferences.selectionAssistantHotKey)
                    Divider()
                    SelectionToolbarPreview(compact: appState.preferences.selectionCompactMode)
                }
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingTitle("功能窗口", icon: "rectangle.inset.filled")
                    Toggle("跟随工具栏", isOn: $appState.preferences.selectionFollowToolbar)
                        .tint(Color.justAccent)
                    Toggle("自动关闭", isOn: $appState.preferences.selectionAutoClose)
                        .tint(Color.justAccent)
                    Toggle("自动置顶", isOn: $appState.preferences.selectionAutoPin)
                        .tint(Color.justAccent)
                    HStack {
                        Text("透明度")
                        Slider(value: $appState.preferences.selectionWindowOpacity, in: 0.2...1.0)
                            .tint(Color.justAccent)
                        Text(appState.preferences.selectionWindowOpacity.formatted(.percent.precision(.fractionLength(0))))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button("保存划词助手设置") {
                appState.persistConfiguration()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.justAccent)
            .focusable(false)
        }
        .padding(28)
        .frame(maxWidth: 860, alignment: .leading)
    }
}

private struct DisplaySettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingTitle("外观", icon: "circle.lefthalf.filled")
                    Picker("外观", selection: $appState.preferences.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }
            }

            Button("保存显示设置") {
                appState.persistConfiguration()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.justAccent)
            .focusable(false)
        }
        .padding(28)
        .frame(maxWidth: 760, alignment: .leading)
    }
}

private struct HotKeySettingsPane: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    settingTitle("全局快捷键", icon: "command")
                    ShortcutTextField(title: "快捷助手", text: $appState.preferences.quickAssistantHotKey)
                    ShortcutTextField(title: "划词助手", text: $appState.preferences.selectionAssistantHotKey)
                    Text("格式示例：Command+Shift+Space、Option+Space、Control+Shift+E。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("保存快捷键设置") {
                appState.persistConfiguration()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.justAccent)
            .focusable(false)
        }
        .padding(28)
        .frame(maxWidth: 760, alignment: .leading)
    }
}

private struct ShortcutTextField: View {
    var title: String
    @Binding var text: String

    var body: some View {
        LabeledContent(title) {
            TextField("Command+Shift+Space", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
        }
    }
}

private struct PlaceholderPane: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 760, alignment: .leading)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Color.justBorderSoft, lineWidth: 1)
            )
            .cardShadow()
    }
}

private func settingTitle(_ title: String, icon: String) -> some View {
    Label(title, systemImage: icon)
        .font(.system(size: 16, weight: .bold))
}

private struct ProviderAvatar: View {
    var provider: ModelProvider

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
            Text(String(provider.name.first ?? "M"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var color: Color {
        switch provider.providerType {
        case .openAI, .openAIResponse:
            .purple
        case .newAPI, .cherryIN:
            .green
        case .anthropic:
            .orange
        case .gemini:
            .blue
        case .azureOpenAI:
            .cyan
        case .ollama:
            .gray
        }
    }
}

private struct SelectionToolbarPreview: View {
    var compact: Bool

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(LinearGradient.justAccent)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                )
                .padding(.horizontal, 10)

            HStack(spacing: compact ? 1 : 3) {
                toolbarItem("character.book.closed", "翻译")
                toolbarItem("questionmark.app", "解释")
                toolbarItem("list.bullet.rectangle", "总结")
            }

            Rectangle()
                .fill(Color.justBorderSoft)
                .frame(width: 1, height: 20)
                .padding(.horizontal, compact ? 4 : 6)

            HStack(spacing: compact ? 1 : 3) {
                toolbarItem("magnifyingglass", "搜索")
                toolbarItem("doc.on.doc", "复制")
            }
        }
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
        )
        .cardShadow()
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func toolbarItem(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            if !compact {
                Text(title)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, compact ? 8 : 11)
        .frame(height: 44)
    }
}
