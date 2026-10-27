import AppKit
import CryptoKit
import Sparkle
import SwiftUI

// KleanTalk: 맥 카카오톡의 광고 자리를 카카오톡과 같은 색의 빈 공간으로 바꾼다.
// 설치하면 (1) /etc/hosts로 카카오 광고 주소를 막고 (2) 광고 요청에 빈 광고를 돌려주는 작은 서버(AdServer/)를
// 이 맥에 띄운다. 켜고 끄는 설정은 없고, 설치하면 작동하고 제거하면 모두 원래대로 돌아간다.
// 로그인 시 --background 인자로 창 없이 실행돼, 설정이 풀렸을 때(macOS 업데이트로 hosts 초기화 등)만 창을 띄운다.
// 새 버전은 Sparkle로 받는다(하루 한 번 확인, EdDSA 서명 확인). 업데이트에 새 서버가 들어 있으면 '다시 설치'로 마무리한다.

let isBackgroundLaunch = CommandLine.arguments.contains("--background")

// MARK: - 언어

enum Language: String { case ko, en }

struct Strings {
    let `continue`: String
    let installTitle: String, installItems: [String], adminNote: String, cancel: String, install: String
    let working: String, notWorking: String, checking: String, notWorkingNote: String, reinstall: String, restarted: String
    let language: String, uninstallButton: String, uninstallTitle: String, uninstallBody: String, uninstall: String
    let adminPrompt: String, missingFiles: String, trustCanceled: String, trustFailed: String
    let checkUpdates: String, serverOutdated: String
    let quit: String, edit: String, cut: String, copy: String, paste: String, selectAll: String, window: String, close: String

    static let ko = Strings(
        continue: "계속",
        installTitle: "KleanTalk 설치",
        installItems: ["카카오톡 광고 주소 차단", "빈 광고를 돌려주는 작은 서버 설치", "serv.ds.kakao.com 전용 인증서 등록"],
        adminNote: "관리자 암호를 두 번 입력합니다", cancel: "취소", install: "설치",
        working: "작동 중", notWorking: "작동하지 않음", checking: "확인 중…",
        notWorkingNote: "설정이 풀렸을 수 있습니다. 다시 설치해 주세요.", reinstall: "다시 설치",
        restarted: "카카오톡을 다시 시작했습니다.",
        language: "언어", uninstallButton: "제거…", uninstallTitle: "KleanTalk을 제거할까요?",
        uninstallBody: "광고 차단과 빈 광고 서버를 모두 지웁니다.", uninstall: "제거",
        adminPrompt: "KleanTalk을 설치하거나 제거하려면 암호가 필요합니다.",
        missingFiles: "앱 안에서 설치 파일을 찾지 못했습니다.",
        trustCanceled: "인증서 등록을 취소했습니다. 다시 설치를 누르세요.",
        trustFailed: "인증서를 등록하지 못했습니다. 다시 설치를 누르세요.",
        checkUpdates: "업데이트 확인…", serverOutdated: "업데이트를 마치려면 다시 설치를 누르세요.",
        quit: "KleanTalk 종료", edit: "편집", cut: "잘라내기", copy: "복사", paste: "붙여넣기", selectAll: "모두 선택",
        window: "윈도우", close: "닫기")

    static let en = Strings(
        continue: "Continue",
        installTitle: "Install KleanTalk",
        installItems: ["Block KakaoTalk ad addresses", "Install a small server that returns blank ads",
                       "Register a certificate for serv.ds.kakao.com only"],
        adminNote: "You’ll enter your password twice", cancel: "Cancel", install: "Install",
        working: "Working", notWorking: "Not working", checking: "Checking…",
        notWorkingNote: "A setting may have been reset. Reinstall to fix it.", reinstall: "Reinstall",
        restarted: "KakaoTalk was restarted.",
        language: "Language", uninstallButton: "Uninstall…", uninstallTitle: "Uninstall KleanTalk?",
        uninstallBody: "Removes ad blocking and the blank ad server.", uninstall: "Uninstall",
        adminPrompt: "KleanTalk needs your password to install or uninstall.",
        missingFiles: "Couldn’t find the installer files inside the app.",
        trustCanceled: "Certificate registration was canceled. Click Reinstall.",
        trustFailed: "Couldn’t register the certificate. Click Reinstall.",
        checkUpdates: "Check for Updates…", serverOutdated: "Click Reinstall to finish the update.",
        quit: "Quit KleanTalk", edit: "Edit", cut: "Cut", copy: "Copy", paste: "Paste", selectAll: "Select All",
        window: "Window", close: "Close")
}

// MARK: - 빈 광고 서버 설치·제거·확인

enum AdServer {
    enum State { case checking, working, notWorking }
    enum Result { case ok, canceled, failed(String) }

    static let host = "serv.ds.kakao.com"
    static var installed: Bool {
        FileManager.default.fileExists(atPath: "/Library/LaunchDaemons/com.myungchul.kleantalk.adserver.plist")
    }

    /// 카카오톡과 같은 경로로 광고를 요청해 본다. hosts·인증서 신뢰·서버가 모두 맞아야 KleanTalk의 빈 광고가 돌아온다.
    static func isWorking() async -> Bool {
        guard let url = URL(string: "https://\(host)/sdk/banner?kleantalk=check") else { return false }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        guard let (_, response) = try? await URLSession(configuration: config).data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return http.value(forHTTPHeaderField: "X-KleanTalk") == "1"   // 빈 광고 서버가 붙이는 표시
    }

    static let certPath = "/Library/Application Support/KleanTalk/AdServer/cert.der"
    static let installedBinaryPath = "/Library/Application Support/KleanTalk/AdServer/kleantalk-adserver"

    /// 앱이 업데이트되면서 앱 안의 서버가 설치된 서버와 달라졌는지. (설치된 서버는 관리자 폴더에 있어 '다시 설치'로 바꾼다)
    static var serverOutdated: Bool {
        guard installed,
              let bundled = Bundle.main.path(forResource: "kleantalk-adserver", ofType: nil).flatMap(FileManager.default.contents(atPath:)),
              let current = FileManager.default.contents(atPath: installedBinaryPath) else { return false }
        return SHA256.hash(data: bundled) != SHA256.hash(data: current)
    }

    static func certificateData() -> Data? { FileManager.default.contents(atPath: certPath) }

    private static func certificate(_ data: Data? = certificateData()) -> SecCertificate? {
        guard let data else { return nil }
        return SecCertificateCreateWithData(nil, data as CFData)
    }

    static func isTrusted(_ data: Data? = certificateData()) -> Bool {
        guard let cert = certificate(data) else { return false }
        var existing: CFArray?
        return SecTrustSettingsCopyTrustSettings(cert, .user, &existing) == errSecSuccess
    }

    /// 서버 인증서를 'serv.ds.kakao.com의 HTTPS 서버 인증'에만 믿도록 이 사용자의 신뢰 설정에 등록한다.
    /// 관리자 권한 스크립트 안에서는 macOS가 확인 창을 띄울 수 없어 거부하므로, 앱이 사용자 권한으로 한다(확인 창이 뜬다).
    static func trustCertificate() -> OSStatus {
        guard let cert = certificate() else { return errSecItemNotFound }
        let setting: [String: Any] = [
            kSecTrustSettingsPolicy as String: SecPolicyCreateSSL(true, host as CFString),
            kSecTrustSettingsPolicyString as String: host,
            kSecTrustSettingsResult as String: SecTrustSettingsResult.trustRoot.rawValue,
        ]
        return SecTrustSettingsSetTrustSettings(cert, .user, [setting] as CFArray)
    }

    /// 등록해 둔 신뢰 설정을 지운다. 설정이 없으면 아무것도 하지 않는다(확인 창도 뜨지 않는다).
    static func untrustCertificate(_ data: Data? = certificateData()) {
        guard isTrusted(data), let cert = certificate(data) else { return }
        SecTrustSettingsRemoveTrustSettings(cert, .user)
    }

    /// 카카오톡이 켜져 있으면 끄고 다시 연다 (새 광고 설정을 바로 받게)
    static func restartKakaoTalk() async -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.kakao.KakaoTalkMac").first,
              let url = app.bundleURL else { return false }
        app.terminate()
        for _ in 0..<50 where !app.isTerminated { try? await Task.sleep(nanoseconds: 200_000_000) }
        guard app.isTerminated else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        return (try? await NSWorkspace.shared.openApplication(at: url, configuration: config)) != nil
    }

    /// 앱 안에 든 설치·제거 스크립트를 관리자 권한으로 실행한다. (암호 창은 macOS가 띄운다)
    static func run(install: Bool, t: Strings) -> Result {
        func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        guard let script = Bundle.main.path(forResource: install ? "install-adserver" : "uninstall-adserver", ofType: "sh"),
              let binary = Bundle.main.path(forResource: "kleantalk-adserver", ofType: nil) else {
            return .failed(t.missingFiles)
        }
        let cmd = "/bin/zsh \(quoted(script)) \(quoted(binary)) 2>&1"
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let source = "do shell script \"\(escape(cmd))\" with administrator privileges with prompt \"\(escape(t.adminPrompt))\""
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        guard let err else { return .ok }
        if (err[NSAppleScript.errorNumber] as? Int) == -128 { return .canceled }
        return .failed(err[NSAppleScript.errorMessage] as? String ?? "")
    }
}

// MARK: - 로그인 시 자동 실행 (설정이 풀렸는지 확인하는 용도)

enum LoginItem {
    static let label = "com.myungchul.kleantalk"

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func set(_ on: Bool) {
        guard on else { try? FileManager.default.removeItem(at: url); return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [Bundle.main.executablePath ?? "", "--background"],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: url)
        }
    }
}

// MARK: - 상태

@MainActor
final class AppModel: ObservableObject {
    enum Screen { case language, install, status, uninstallConfirm }

    @Published var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language"); onLanguageChange?() }
    }
    @Published var screen: Screen
    @Published var state: AdServer.State = .checking
    @Published var busy = false
    @Published var error: String?
    @Published var restartedKakao = false
    @Published var serverOutdated = false
    var onLanguageChange: (() -> Void)?

    var t: Strings { language == .ko ? .ko : .en }

    init() {
        language = Language(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .ko
        // 설치돼 있으면 상태 화면, 아니면 언어부터 묻는다
        screen = AdServer.installed ? .status : .language
        // 개발용: 화면 확인·스크린샷을 위해 시작 화면과 언어를 고른다 (KLEANTALK_PREVIEW=language|install|status|uninstall, KLEANTALK_LANG=ko|en)
        let env = ProcessInfo.processInfo.environment
        if let lang = env["KLEANTALK_LANG"].flatMap(Language.init(rawValue:)) { language = lang }
        switch env["KLEANTALK_PREVIEW"] {
        case "language": screen = .language
        case "install": screen = .install
        case "status": screen = .status; preview = true
        case "uninstall": screen = .uninstallConfirm
        default: break
        }
    }

    /// 개발용 미리 보기 중에는 실제 상태를 확인하지 않고 '작동 중'으로 보여 준다
    private var preview = false

    func check() async {
        if preview { state = .working; return }
        guard AdServer.installed else { state = .notWorking; return }
        serverOutdated = AdServer.serverOutdated
        if state != .working { state = .checking }
        state = await AdServer.isWorking() ? .working : .notWorking
    }

    func install() {
        busy = true; error = nil
        let oldCert = AdServer.certificateData()
        switch AdServer.run(install: true, t: t) {
        case .ok:
            LoginItem.set(true)
            screen = .status
            // 인증서가 새로 만들어졌을 때만 신뢰를 (다시) 등록한다. 그대로면 확인 창 없이 넘어간다.
            let newCert = AdServer.certificateData()
            if let oldCert, oldCert != newCert { AdServer.untrustCertificate(oldCert) }
            let status = AdServer.isTrusted(newCert) ? errSecSuccess : AdServer.trustCertificate()
            if status == errSecSuccess {
                Task {
                    restartedKakao = await AdServer.restartKakaoTalk()
                    await check()
                }
            } else {
                error = status == errAuthorizationCanceled ? t.trustCanceled : "\(t.trustFailed) (\(status))"
                Task { await check() }
            }
        case .canceled:
            break
        case .failed(let message):
            error = message.isEmpty ? nil : message
        }
        busy = false
    }

    func uninstall() {
        busy = true; error = nil
        AdServer.untrustCertificate()
        switch AdServer.run(install: false, t: t) {
        case .ok:
            LoginItem.set(false)
            if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
            // 앱도 휴지통으로 옮기고 끝낸다
            NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        case .canceled:
            screen = .status
        case .failed(let message):
            error = message.isEmpty ? nil : message
            screen = .status
        }
        busy = false
    }
}

// MARK: - 화면 (모든 창은 같은 크기)

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            switch model.screen {
            case .language: LanguageView(model: model)
            case .install: InstallView(model: model)
            case .status: StatusView(model: model)
            case .uninstallConfirm: UninstallView(model: model)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 440, height: 190, alignment: .topLeading)
    }
}

struct Header<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
            content
        }
    }
}

struct LanguageView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header { Text("언어 · Language").font(.headline) }
            Picker("", selection: $model.language) {
                Text("한국어").tag(Language.ko)
                Text("English").tag(Language.en)
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .labelsHidden()
            .padding(.top, 20)
            Spacer()
            HStack {
                Spacer()
                Button(model.t.continue) { model.screen = .install }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct InstallView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let t = model.t
        VStack(alignment: .leading, spacing: 0) {
            Header { Text(t.installTitle).font(.headline) }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(t.installItems, id: \.self) { Text("•  " + $0) }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 10)
            Spacer()
            HStack(spacing: 8) {
                Text(model.error ?? t.adminNote)
                    .font(.caption)
                    .foregroundStyle(model.error == nil ? Color.secondary : Color.red)
                    .lineLimit(2)
                Spacer()
                Button(t.cancel) { NSApp.terminate(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(t.install) { model.install() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(model.busy)
        }
    }
}

struct StatusView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let t = model.t
        let (label, symbol, color): (String, String, Color) = switch model.state {
        case .working: (t.working, "checkmark.circle.fill", .green)
        case .notWorking: (t.notWorking, "exclamationmark.triangle.fill", .orange)
        case .checking: (t.checking, "circle.dotted", .secondary)
        }
        VStack(alignment: .leading, spacing: 0) {
            Header {
                VStack(alignment: .leading, spacing: 2) {
                    Text("KleanTalk").font(.headline)
                    Label(label, systemImage: symbol).foregroundStyle(color).font(.callout)
                }
            }
            HStack(spacing: 10) {
                Text(t.language).foregroundStyle(.secondary)
                Picker("", selection: $model.language) {
                    Text("한국어").tag(Language.ko)
                    Text("English").tag(Language.en)
                }
                .labelsHidden()
                .frame(width: 150)
            }
            .padding(.top, 18)
            Spacer()
            HStack(spacing: 8) {
                if let error = model.error {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                } else if model.serverOutdated {
                    Text(t.serverOutdated).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else if model.state == .notWorking {
                    Text(t.notWorkingNote).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else if model.restartedKakao && model.state == .working {
                    Text(t.restarted).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if model.state == .notWorking || model.serverOutdated {
                    Button(t.reinstall) { model.install() }
                }
                Button(t.uninstallButton, role: .destructive) { model.error = nil; model.screen = .uninstallConfirm }
            }
            .disabled(model.busy)
        }
        .task { await model.check() }
    }
}

struct UninstallView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let t = model.t
        VStack(alignment: .leading, spacing: 0) {
            Header { Text(t.uninstallTitle).font(.headline) }
            Text(t.uninstallBody).font(.callout).foregroundStyle(.secondary).padding(.top, 12)
            Spacer()
            HStack(spacing: 8) {
                Spacer()
                Button(t.cancel) { model.screen = .status }
                    .keyboardShortcut(.cancelAction)
                Button(t.uninstall, role: .destructive) { model.uninstall() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .disabled(model.busy)
        }
    }
}

// MARK: - 앱

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.myungchul.kleantalk"
    private static let showWindowNotification = Notification.Name(bundleID + ".showWindow")

    static func main() {
        let app = NSApplication.shared
        let pid = ProcessInfo.processInfo.processIdentifier
        // 이미 실행 중이면 그쪽에 창을 띄우라고 알리고 끝낸다 (로그인 때 뜬 백그라운드 실행과 겹치지 않게)
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: {
            $0.processIdentifier != pid && !$0.isTerminated
        }) {
            if !isBackgroundLaunch {
                DistributedNotificationCenter.default().postNotificationName(
                    showWindowNotification, object: bundleID, userInfo: nil, deliverImmediately: true)
            }
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        DistributedNotificationCenter.default().addObserver(
            delegate, selector: #selector(showWindowRequested(_:)), name: showWindowNotification, object: bundleID)
        app.run()
        DistributedNotificationCenter.default().removeObserver(delegate)
    }

    private var model: AppModel!
    private var window: NSWindow?
    private var updater: SPUStandardUpdaterController!
    private var showWindowWhenReady = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        model.onLanguageChange = { [weak self] in self?.buildMenu() }
        updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        if ProcessInfo.processInfo.environment["KLEANTALK_UPDATE_TEST"] != nil {
            // 개발용: 업데이트를 바로 확인해 창 없이 받고, 받자마자 설치·재실행한다
            updater.updater.automaticallyDownloadsUpdates = true
            updater.updater.checkForUpdatesInBackground()
        }
        buildMenu()
        if isBackgroundLaunch {
            NSApp.setActivationPolicy(.accessory)
            Task { await checkAndShowIfBroken() }
        }
        if !isBackgroundLaunch || showWindowWhenReady {
            showWindowWhenReady = false
            showWindow()
        }
        // 켜져 있는 동안 6시간마다 설정이 풀리지 않았는지 확인한다
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkAndShowIfBroken() }
        }
    }

    private func checkAndShowIfBroken() async {
        guard AdServer.installed else { return }
        await model.check()
        if model.state == .notWorking || model.serverOutdated { model.screen = .status; showWindow() }
    }

    // MARK: 업데이트 (Sparkle)

    /// 개발용: 시험할 때만 업데이트 목록 주소를 바꾼다 (KLEANTALK_FEED). 평소에는 Info.plist의 SUFeedURL.
    func feedURLString(for updater: SPUUpdater) -> String? { ProcessInfo.processInfo.environment["KLEANTALK_FEED"] }

    /// 창 없이 도는 동안에도 업데이트 창이 다른 창 뒤에 숨지 않게 한다
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func standardUserDriverWillFinishUpdateSession() {
        if window?.isVisible != true && AdServer.installed { NSApp.setActivationPolicy(.accessory) }
    }

    @objc private func checkForUpdates(_ sender: Any?) { updater.checkForUpdates(sender) }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        guard ProcessInfo.processInfo.environment["KLEANTALK_UPDATE_TEST"] != nil else { return false }
        immediateInstallationBlock()
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        requestWindow()
        return true
    }

    @objc private func showWindowRequested(_ notification: Notification) { requestWindow() }

    private func requestWindow() {
        guard model != nil else { showWindowWhenReady = true; return }
        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowWillClose(_ notification: Notification) {
        // 설치 전이면 끝낸다. 설치 후에는 창 없이 남아 가끔 상태를 확인한다.
        if AdServer.installed { NSApp.setActivationPolicy(.accessory) } else { NSApp.terminate(nil) }
    }

    private func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 190),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "KleanTalk"
            w.isReleasedWhenClosed = false
            if ProcessInfo.processInfo.environment["KLEANTALK_SNAPSHOT"] != nil {
                // 스냅숏은 창이 맨 앞이 아니어도 활성 창 모양(파란 기본 버튼)으로 그린다
                w.contentView = NSHostingView(rootView: RootView(model: model).environment(\.controlActiveState, .key))
            } else {
                w.contentView = NSHostingView(rootView: RootView(model: model))
            }
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        if let path = ProcessInfo.processInfo.environment["KLEANTALK_SNAPSHOT"] { snapshot(to: path) }
    }

    /// 개발용: 창 내용을 2배 크기 PNG로 저장하고 끝낸다 (소개 이미지·문서용, KLEANTALK_SNAPSHOT=<파일>)
    private func snapshot(to path: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let view = self?.window?.contentView else { NSApp.terminate(nil); return }
            let size = view.bounds.size
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { NSApp.terminate(nil); return }
            rep.size = size
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
        }
    }

    private func buildMenu() {
        let t = model.t
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: t.checkUpdates, action: #selector(checkForUpdates(_:)), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: t.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: t.edit)
        edit.addItem(withTitle: t.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: t.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: t.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: t.selectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: t.window)
        windowMenu.addItem(withTitle: t.close, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
