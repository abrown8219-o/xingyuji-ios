import Foundation
import Observation
import WebKit

// MARK: - 站点模型

struct Site: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var url: String

    init(id: String = UUID().uuidString, name: String = "", url: String = "") {
        self.id = id
        self.name = name
        self.url = url
    }

    var displayName: String { name.isEmpty ? url : name }
    var host: String { URL(string: url)?.host ?? "" }
}

// MARK: - 全局状态

@MainActor
@Observable
final class AppStore {
    var sites: [Site] = []
    var activeId: String = ""

    // 设置
    var autoOpen = false
    var debugBtn = true
    var backBtn = true
    var debugBtnX: Double = -1   // -1 = 用默认位置
    var debugBtnY: Double = -1
    var backBtnX: Double = -1
    var backBtnY: Double = -1
    var updateBase = ""

    // 调试日志环
    var logs: [String] = []

    init() {
        load()
        if sites.isEmpty {
            // 首次运行：预置星语星愿
            let s = Site(name: "星语星愿", url: "https://64848736.cfd")
            sites = [s]
            activeId = s.id
            persist()
        }
    }

    var activeSite: Site? {
        if let s = sites.first(where: { $0.id == activeId }) { return s }
        return sites.first
    }

    // MARK: 站点管理

    @discardableResult
    func saveSite(id: String?, name: String, url: String) -> Site? {
        let clean = Self.sanitize(url)
        guard !clean.isEmpty else { return nil }
        if let id, let idx = sites.firstIndex(where: { $0.id == id }) {
            var s = sites[idx]
            s.name = name
            s.url = clean
            sites[idx] = s
            persist()
            return s
        }
        let s = Site(name: name, url: clean)
        sites.append(s)
        persist()
        return s
    }

    func deleteSite(_ id: String) {
        sites.removeAll { $0.id == id }
        if activeId == id { activeId = sites.first?.id ?? "" }
        persist()
    }

    func setActive(_ id: String) {
        activeId = id
        persist()
    }

    static func sanitize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        let low = s.lowercased()
        if !low.hasPrefix("http://") && !low.hasPrefix("https://") {
            s = "https://" + s
        }
        return s
    }

    // MARK: 日志

    func log(_ tag: String, _ msg: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        logs.append("\(f.string(from: Date())) [\(tag)] \(msg)")
        if logs.count > 2000 { logs.removeFirst(logs.count - 2000) }
    }

    // MARK: JS 桥 getState 的返回

    func stateJSON(site: Site?) -> String {
        var root: [String: Any] = ["activeId": activeId]
        if let site {
            root["site"] = ["id": site.id, "name": site.displayName, "url": site.url]
        }
        root["sites"] = sites.map { ["id": $0.id, "name": $0.displayName, "url": $0.url] }
        if let d = try? JSONSerialization.data(withJSONObject: root),
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        return "{}"
    }

    // MARK: 持久化

    func persist() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(sites) { d.set(data, forKey: "sites") }
        d.set(activeId, forKey: "activeId")
        d.set(autoOpen, forKey: "autoOpen")
        d.set(debugBtn, forKey: "debugBtn")
        d.set(backBtn, forKey: "backBtn")
        d.set(debugBtnX, forKey: "debugBtnX")
        d.set(debugBtnY, forKey: "debugBtnY")
        d.set(backBtnX, forKey: "backBtnX")
        d.set(backBtnY, forKey: "backBtnY")
        d.set(updateBase, forKey: "updateBase")
    }

    private func load() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: "sites"),
           let s = try? JSONDecoder().decode([Site].self, from: data) {
            sites = s
        }
        activeId = d.string(forKey: "activeId") ?? ""
        autoOpen = d.bool(forKey: "autoOpen")
        debugBtn = d.object(forKey: "debugBtn") == nil ? true : d.bool(forKey: "debugBtn")
        backBtn = d.object(forKey: "backBtn") == nil ? true : d.bool(forKey: "backBtn")
        debugBtnX = d.double(forKey: "debugBtnX"); if debugBtnX == 0 { debugBtnX = -1 }
        debugBtnY = d.double(forKey: "debugBtnY"); if debugBtnY == 0 { debugBtnY = -1 }
        backBtnX = d.double(forKey: "backBtnX"); if backBtnX == 0 { backBtnX = -1 }
        backBtnY = d.double(forKey: "backBtnY"); if backBtnY == 0 { backBtnY = -1 }
        updateBase = d.string(forKey: "updateBase") ?? ""
    }
}

// MARK: - Basic Auth 凭证（按 host 存，等同安卓 AuthStore）

enum AuthStore {
    static func get(_ host: String) -> (String, String)? {
        let d = UserDefaults.standard
        let u = d.string(forKey: "auth|\(host)|u") ?? ""
        let p = d.string(forKey: "auth|\(host)|p") ?? ""
        return (u.isEmpty && p.isEmpty) ? nil : (u, p)
    }

    static func save(_ host: String, _ user: String, _ pass: String) {
        let d = UserDefaults.standard
        d.set(user, forKey: "auth|\(host)|u")
        d.set(pass, forKey: "auth|\(host)|p")
    }

    static func remove(_ host: String) {
        let d = UserDefaults.standard
        d.removeObject(forKey: "auth|\(host)|u")
        d.removeObject(forKey: "auth|\(host)|p")
    }
}

// MARK: - 清除站点数据

enum WebDataClearer {
    static func clearAll() async {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        await store.removeData(ofTypes: types, for: records)
    }

    static func clear(host: String) async {
        guard !host.isEmpty else { return }
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let target = records.filter { $0.displayName.contains(host) }
        await store.removeData(ofTypes: types, for: target)
    }
}
