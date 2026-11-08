import SwiftUI

// 打开网页用的目标（fullScreenCover 需要 Identifiable）
struct WebTarget: Identifiable {
    let id = UUID()
    let site: Site
    let incognito: Bool
}

struct MainScreen: View {
    @Environment(AppStore.self) private var store
    @State private var editing: Site?
    @State private var showingEditor = false
    @State private var webTarget: WebTarget?
    @State private var toast: String?
    @State private var checking = false

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section("站点") {
                    ForEach(store.sites) { site in
                        row(site)
                    }
                    .onDelete(perform: delete)
                    Button {
                        editing = nil
                        showingEditor = true
                    } label: {
                        Label("添加站点", systemImage: "plus")
                    }
                }

                Section("设置") {
                    Toggle("启动时自动打开上次站点", isOn: $store.autoOpen)
                    Toggle("🐞 调试按钮（网页页内，可拖动）", isOn: $store.debugBtn)
                    Toggle("‹ 悬浮返回按钮（可拖动）", isOn: $store.backBtn)
                }

                Section {
                    Button("检查更新") { checkUpdate() }
                    Button("⬆ 上传日志给开发者") { uploadLog() }
                }

                Section {
                    Text("v\(Self.version) · xingyuji · iOS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("星语机")
            .sheet(isPresented: $showingEditor) {
                SiteEditor(site: editing) { name, url in
                    if let s = store.saveSite(id: editing?.id, name: name, url: url) {
                        store.setActive(s.id)
                    } else {
                        toast = "网址无效"
                    }
                }
            }
            .fullScreenCover(item: $webTarget) { target in
                WebScreen(site: target.site, incognito: target.incognito)
            }
            .alert("提示", isPresented: Binding(
                get: { toast != nil },
                set: { if !$0 { toast = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(toast ?? "")
            }
            .task {
                // 启动时自动打开
                if store.autoOpen, let s = store.activeSite {
                    webTarget = WebTarget(site: s, incognito: false)
                }
            }
        }
    }

    // MARK: 站点行

    private func row(_ site: Site) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(site.displayName).font(.body)
                Text(site.url).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if site.id == store.activeId {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open(site, incognito: false) }
        .contextMenu {
            Button("打开") { open(site, incognito: false) }
            Button("无痕打开") { open(site, incognito: true) }
            Button("设为默认") { store.setActive(site.id) }
            Button("在 Safari 打开") {
                if let u = URL(string: site.url) { UIApplication.shared.open(u) }
            }
            Button("编辑", systemImage: "pencil") {
                editing = site
                showingEditor = true
            }
            Button("删除", systemImage: "trash", role: .destructive) {
                store.deleteSite(site.id)
            }
        }
    }

    private func open(_ site: Site, incognito: Bool) {
        store.setActive(site.id)
        webTarget = WebTarget(site: site, incognito: incognito)
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets {
            store.deleteSite(store.sites[i].id)
        }
    }

    // MARK: 更新 / 上传

    private func checkUpdate() {
        guard !checking else { return }
        checking = true
        Task {
            let info = await Updater.check()
            checking = false
            toast = info.message
        }
    }

    private func uploadLog() {
        let content = store.logs.joined(separator: "\n")
        Task {
            let msg = await LogUploader.upload(content)
            toast = msg
        }
    }
}

// MARK: - 站点编辑页

struct SiteEditor: View {
    let site: Site?
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""

    init(site: Site?, onSave: @escaping (String, String) -> Void) {
        self.site = site
        self.onSave = onSave
        _name = State(initialValue: site?.name ?? "")
        _url = State(initialValue: site?.url ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称（可留空，显示网址）") {
                    TextField("星语星愿", text: $name)
                }
                Section("网址") {
                    TextField("https://", text: $url)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(site == nil ? "添加站点" : "编辑站点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(name, url)
                        dismiss()
                    }
                }
            }
        }
    }
}
