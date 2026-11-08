import Foundation

// MARK: - 日志上传（等同安卓 LogUploadRun）

enum LogUploader {
    static let base = "https://64848736.cfd"
    static let key = "xylog-d3f0705e30b6ab66e52d33aa"

    static func upload(_ content: String) async -> String {
        let deviceId = deviceID()
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        let name = "\(deviceId)_\(f.string(from: Date())).txt"
        guard let url = URL(string: "\(base)/logs/\(name)") else {
            return "上传失败：地址无效"
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(key, forHTTPHeaderField: "X-Log-Key")
        req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = content.data(using: .utf8)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) {
                return "上传成功：\(name)"
            }
            return "上传失败：HTTP \(code)"
        } catch {
            return "上传失败：\(error.localizedDescription)"
        }
    }

    /// 稳定设备标识（存 UserDefaults，首次生成）
    static func deviceID() -> String {
        let d = UserDefaults.standard
        if let v = d.string(forKey: "deviceId") { return v }
        let v = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        d.set(v, forKey: "deviceId")
        return v
    }
}

// MARK: - 更新检查（读 version.json；iOS 无法自装，只提示）

struct UpdateInfo {
    var ok: Bool = false
    var versionName: String = ""
    var notes: String = ""
    var message: String = ""
}

enum Updater {
    static func check() async -> UpdateInfo {
        let urls = [
            "https://64848736.cfd/app/version.json"
        ]
        for u in urls {
            guard let url = URL(string: u) else { continue }
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            req.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200,
                      let text = String(data: data, encoding: .utf8),
                      text.trimmingCharacters(in: .whitespacesAndNewlines).first != "<",
                      text.contains("versionCode") else {
                    continue
                }
                var info = UpdateInfo()
                info.ok = true
                info.versionName = field(text, "versionName")
                info.notes = field(text, "notes")
                if info.notes.isEmpty { info.notes = "（无说明）" }
                info.message = "网页最新版本 v\(info.versionName)\n\(info.notes)\n\niOS 壳应用更新需通过 TestFlight / App Store，无法像安卓那样自动安装。"
                return info
            } catch {
                continue
            }
        }
        return UpdateInfo(message: "检查更新失败：无法连接更新服务器")
    }

    /// 简单 JSON 字符串字段解析（等同安卓的正则解析）
    private static func field(_ json: String, _ key: String) -> String {
        let pattern = "\"\(key)\"\\s*:\\s*\"([^\"]*)\""
        guard let re = try? NSRegularExpression(pattern: pattern) else { return "" }
        let ns = json as NSString
        guard let m = re.firstMatch(in: json, range: NSRange(location: 0, length: ns.length)) else {
            return ""
        }
        var v = ns.substring(with: m.range(at: 1))
        v = v.replacingOccurrences(of: "\\n", with: "\n")
        v = v.replacingOccurrences(of: "\\t", with: "\t")
        v = v.replacingOccurrences(of: "\\\"", with: "\"")
        return v
    }
}
