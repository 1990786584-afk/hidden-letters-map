import SwiftUI
import MapKit

// ZFxF 奶油蜜桃粉：暖粉色，不使用偏紫的豆沙色。
enum LovePalette {
    static let background = Color(red: 1.0, green: 0.965, blue: 0.957)   // #FFF6F4
    static let blush = Color(red: 1.0, green: 0.894, blue: 0.902)        // #FFE4E6
    static let accent = Color(red: 0.863, green: 0.447, blue: 0.569)     // #DC7291
    static let envelope = Color(red: 0.965, green: 0.702, blue: 0.741)   // #F6B3BD
}

// 用原生矢量图替换不可控颜色的 💌 Emoji，信封与爱心都能呈现暖粉色。
struct PinkLetter: View {
    var size: CGFloat = 54
    var body: some View {
        ZStack {
            Image(systemName: "envelope.fill")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(LovePalette.envelope)
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.33, weight: .medium))
                .foregroundStyle(LovePalette.accent)
                .offset(y: -size * 0.045)
        }
        .accessibilityLabel("粉色爱心信封")
    }
}

@main
struct ZFxFLoveMapApp: App {
    @StateObject private var session = LoveMapSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .tint(LovePalette.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var session: LoveMapSession

    var body: some View {
        Group {
            if session.connected {
                TabView {
                    TreasureMapView()
                        .tabItem { Label("藏宝地图", systemImage: "map") }
                    DateBoardView()
                        .tabItem { Label("约会板", systemImage: "heart.text.square") }
                    DateCardsView()
                        .tabItem { Label("约会来信", systemImage: "envelope.badge") }
                    ConnectionInfoView()
                        .tabItem { Label("设置", systemImage: "gearshape") }
                }
            } else {
                ConnectionSetupView()
            }
        }
        .preferredColorScheme(.light)
    }
}

struct ConnectionSetupView: View {
    @EnvironmentObject private var session: LoveMapSession
    @State private var address = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 50)
                    PinkLetter(size: 82).frame(height: 94)
                    VStack(spacing: 10) {
                        Text("ZFxF · Love Map")
                            .font(.system(size: 31, weight: .medium, design: .serif))
                        Text("Somewhere, With You.")
                            .font(.system(size: 14, design: .serif))
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 15) {
                        Text("连接我们的藏宝服务器")
                            .font(.headline)
                        TextField("https://memory.ryanecho.xyz/zfxf", text: $address)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.URL)
                            .padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        SecureField("藏宝地图密码", text: $password)
                            .textContentType(.password)
                            .padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        Text("服务器已配置 HTTPS。请使用我们独立的 ZFxF 密码连接；之后会安全保存到 iPhone 钥匙串，不需要每次输入。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let error = session.error {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                        Button {
                            Task { await session.connect(address: address, password: password) }
                        } label: {
                            if session.connecting { ProgressView().tint(.white) }
                            else { Text("打开我们的约会地图 ♡") }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(LovePalette.accent, in: Capsule())
                        .disabled(session.connecting)
                    }
                    .padding(21)
                    .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 22))
                    Spacer(minLength: 40)
                }
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(LovePalette.background)
        }
        .onAppear { address = session.serverAddress }
    }
}

struct ConnectionInfoView: View {
    @EnvironmentObject private var session: LoveMapSession

    var body: some View {
        NavigationStack {
            Form {
                Section("我们的藏宝服务器") {
                    Text(session.serverAddress)
                        .font(.footnote)
                        .textSelection(.enabled)
                    Button("退出连接", role: .destructive) { session.disconnect() }
                }
                Section("关于 ZFxF") {
                    Text("藏宝地图、约会板、回忆照片。")
                    Text("导航和地铁到站提醒暂时不做。")
                }
            }
            .navigationTitle("我们的设置")
        }
    }
}

struct TreasureMapView: View {
    @EnvironmentObject private var session: LoveMapSession
    @StateObject private var locator = TreasureLocation()
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                           span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08))
    )
    @State private var treasure: TreasureMap?
    @State private var selected: HiddenLetter?
    @State private var error: String?
    @State private var loading = false
    @State private var opening = false
    @State private var openMessage: String?
    @State private var showingShareConfirmation = false
    @State private var sharingLocation = false
    @State private var waitingForFreshLocation = false
    @State private var sharedLocation: SharedLocation?
    @State private var shareMessage: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $camera) {
                    if let treasure {
                        ForEach(treasure.letters) { letter in
                            if let coordinate = letter.coordinate {
                                Annotation(letter.place ?? "神秘的信", coordinate: coordinate) {
                                    Button {
                                        openMessage = nil
                                        selected = letter
                                    } label: {
                                        Text(letter.isSealed ? "💌" : "💗")
                                            .font(.system(size: 24))
                                            .padding(8)
                                            .background(.white, in: Circle())
                                            .shadow(radius: 4)
                                    }
                                    .accessibilityLabel(letter.isSealed ? "未解锁的信" : letter.place ?? "已解锁的信")
                                }
                            }
                        }
                        ForEach(treasure.stops) { stop in
                            Annotation(stop.name, coordinate: .init(latitude: stop.lat, longitude: stop.lon)) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(LovePalette.accent, .white)
                            }
                        }
                    }
                }
                .mapControls { MapCompass(); MapScaleView() }
                VStack(spacing: 8) {
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                            .padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let notice = locator.notice {
                        Text(notice).font(.footnote)
                            .padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if treasure?.letters.isEmpty == true {
                        Text("地图还没有藏信。等哥哥先藏一封给你 ♡")
                            .font(.subheadline)
                            .padding(15)
                            .frame(maxWidth: .infinity)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "location.circle.fill")
                                .foregroundStyle(LovePalette.accent)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("分享我的位置给 Finnian ♡")
                                    .font(.subheadline.weight(.semibold))
                                Text(sharedLocation == nil
                                     ? "只在你按下分享时发送一次，绝不自动追踪。"
                                     : "已分享最新位置 · 24 小时内有效")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }

                        HStack(spacing: 10) {
                            Button {
                                showingShareConfirmation = true
                            } label: {
                                if sharingLocation || waitingForFreshLocation {
                                    ProgressView().tint(.white)
                                } else {
                                    Label(sharedLocation == nil ? "分享这一次" : "重新分享", systemImage: "location.fill")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(sharingLocation || waitingForFreshLocation)

                            if sharedLocation != nil {
                                Button("撤回分享", role: .destructive) {
                                    Task { await revokeShare() }
                                }
                                .buttonStyle(.bordered)
                                .disabled(sharingLocation || waitingForFreshLocation)
                            }
                        }
                        if let shareMessage {
                            Text(shareMessage).font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    HStack {
                        Label("\(treasure?.letters.count ?? 0) 封藏起来的心意", systemImage: "envelope")
                        Spacer()
                        Button {
                            locator.locate()
                            if let here = locator.location {
                                camera = .region(MKCoordinateRegion(center: here.coordinate, span:
                                    MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))
                            }
                        } label: {
                            Label("定位我", systemImage: "location")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .font(.subheadline)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding()
            }
            .navigationTitle("藏宝地图 ♡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button { Task { await loadMap() } } label: {
                    if loading { ProgressView() }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(loading)
            }
            .sheet(item: $selected) { letter in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(letter.status == "opened" ? "💗" : "💌")
                                .font(.system(size: 56))
                                .frame(maxWidth: .infinity)
                            Text(letter.place ?? "藏在某个地方的秘密")
                                .font(.title2.weight(.medium))
                            Text(letter.hint)
                                .font(.body)
                                .foregroundStyle(.secondary)
                            if let body = letter.body, !body.isEmpty {
                                Text(body).padding(16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                            }
                            if let openMessage { Text(openMessage).font(.footnote) }
                            if letter.status != "opened" {
                                Button {
                                    Task { await open(letter) }
                                } label: {
                                    if opening { ProgressView() }
                                    else { Text("我到这里啦，拆开信 ♡") }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(opening)
                                Text("靠近藏宝点并允许定位才能拆开。地图上的模糊圈不是精确位置。")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(22)
                    }
                    .background(LovePalette.background)
                    .navigationTitle("一封给你的信")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { selected = nil }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .task {
            await loadMap()
            await refreshShareStatus()
            locator.locate() // Only local map display; NO upload.
        }
        .confirmationDialog(
            "把此刻的位置分享给 Finnian？",
            isPresented: $showingShareConfirmation,
            titleVisibility: .visible
        ) {
            Button("确认分享这一次") { requestOneTimeShare() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会将当前坐标和定位精度发送到你的私人美国 VPS。服务器只保留最新一次分享，24 小时后失效；你可以随时撤回。不启用后台追踪。")
        }
        .onChange(of: locator.location) { _, newLocation in
            guard let newLocation else { return }
            camera = .region(MKCoordinateRegion(center: newLocation.coordinate,
                       span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))
            if waitingForFreshLocation && validForShare(newLocation) {
                waitingForFreshLocation = false
                Task { await uploadShare(newLocation) }
            }
        }
        .onChange(of: locator.notice) { _, newValue in
            if waitingForFreshLocation, let newValue {
                waitingForFreshLocation = false
                shareMessage = newValue
            }
        }
    }

    // We never send a cached or invalid location, even if MapKit can display it.
    private func validForShare(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0 &&
        location.horizontalAccuracy <= 2000 &&
        abs(location.timestamp.timeIntervalSinceNow) <= 60 &&
        CLLocationCoordinate2DIsValid(location.coordinate)
    }

    @MainActor
    private func requestOneTimeShare() {
        shareMessage = nil
        if let location = locator.location, validForShare(location) {
            Task { await uploadShare(location) }
            return
        }
        // Only the button starts this pending request; map opening cannot start sharing.
        waitingForFreshLocation = true
        shareMessage = "正在获取新的定位，等一小会儿就好……"
        locator.locate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            if waitingForFreshLocation {
                waitingForFreshLocation = false
                shareMessage = "暂时没拿到准确定位，稍后再点一次分享。"
            }
        }
    }

    @MainActor
    private func uploadShare(_ location: CLLocation) async {
        guard !sharingLocation, let api = session.api else { return }
        sharingLocation = true
        defer { sharingLocation = false }
        do {
            sharedLocation = try await api.shareLocationOnce(location)
            shareMessage = "分享成功啦！仅保存最新位置，24 小时后自动失效。"
        } catch {
            shareMessage = "发送失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func refreshShareStatus() async {
        guard let api = session.api else { return }
        do {
            sharedLocation = try await api.currentSharedLocation()
        } catch {
            shareMessage = "暂时没能读取分享状态：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func revokeShare() async {
        guard let api = session.api, !sharingLocation else { return }
        sharingLocation = true
        defer { sharingLocation = false }
        do {
            try await api.revokeSharedLocation()
            sharedLocation = nil
            shareMessage = "已经撤回。服务器不再保留这一条共享位置。"
        } catch {
            shareMessage = "撤回失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadMap() async {
        guard let api = session.api else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await api.treasureMap()
            treasure = result
            error = nil
            if let coordinate = result.stops.first.map({ CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                ?? result.letters.compactMap(\.coordinate).first {
                camera = .region(MKCoordinateRegion(center: coordinate,
                              span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func open(_ letter: HiddenLetter) async {
        guard let api = session.api else { return }
        guard let position = locator.location else {
            locator.locate()
            openMessage = "正在确认你的位置，等定位完成后再点一次。"
            return
        }
        opening = true
        defer { opening = false }
        do {
            let result = try await api.openLetter(letter.id, position: position)
            if result.ok {
                selected = result.letter
                openMessage = nil
                await loadMap()
            } else if let away = result.awayM {
                openMessage = "还差大约 \(away) 米才能解锁这封信。"
            } else {
                openMessage = "今天的到访已记下，继续期待下一次解锁 ♡"
            }
        } catch {
            openMessage = error.localizedDescription
        }
    }
}
