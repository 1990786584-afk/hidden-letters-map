import SwiftUI
import MapKit

// ZFxF · Our Little Universe
// Real home/school coordinates are stored only on the authenticated private VPS.
struct SavedPlacesView: View {
    @EnvironmentObject private var session: LoveMapSession
    @State private var places: [SavedPlace] = []
    @State private var editor: PlaceEditorTarget?
    @State private var error: String?
    @State private var loading = false

    struct PlaceEditorTarget: Identifiable {
        let id = UUID()
        let place: SavedPlace?
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 7) {
                    Text("我们的秘密宇宙 ♡")
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundStyle(LovePalette.accent)
                    Text("在家、学校、迪士尼、常走的公园……给每个熟悉的角落起一个名字。以后只说「我在家」，就能用预存位置安排惊喜。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("地点只有你主动保存时才会上传私人 VPS；不会自动定位或分享你现在在哪里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
            }
            Section("我的地点 · \(places.count)") {
                if places.isEmpty && !loading {
                    Text("还没有地点。先添加「家」或「学校」，也可以保存安全、方便步行的公园作为惊喜目的地。")
                        .foregroundStyle(.secondary)
                }
                ForEach(places) { place in
                    Button {
                        editor = PlaceEditorTarget(place: place)
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: icon(for: place.kind))
                                .font(.title3)
                                .foregroundStyle(LovePalette.accent)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.label)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if !place.note.isEmpty {
                                    Text(place.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            Task { await remove(place) }
                        }
                    }
                }
            }
            if let error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LovePalette.background)
        .navigationTitle("秘密地点 ♡")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor = PlaceEditorTarget(place: nil) } label: {
                    Label("新增地点", systemImage: "plus")
                }
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(item: $editor) { target in
            NavigationStack {
                SavedPlaceEditorView(existing: target.place) {
                    editor = nil
                    Task { await reload() }
                }
                .environmentObject(session)
            }
        }
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "home": return "house.fill"
        case "school": return "graduationcap.fill"
        case "outing": return "sparkles"
        case "walk": return "figure.walk"
        default: return "mappin.and.ellipse"
        }
    }

    @MainActor
    private func reload() async {
        guard let api = session.api else { return }
        loading = true
        defer { loading = false }
        do {
            places = try await api.savedPlaces()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func remove(_ place: SavedPlace) async {
        guard let api = session.api else { return }
        do {
            try await api.deleteSavedPlace(id: place.id)
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SavedPlaceEditorView: View {
    @EnvironmentObject private var session: LoveMapSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locator = TreasureLocation()

    let existing: SavedPlace?
    let onSaved: () -> Void

    @State private var name: String
    @State private var kind: String
    @State private var note: String
    @State private var searchText = ""
    @State private var camera: MapCameraPosition
    @State private var mapCenter: CLLocationCoordinate2D
    @State private var picked: CLLocationCoordinate2D?
    @State private var status: String?
    @State private var saving = false
    @State private var searching = false
    @State private var locating = false

    init(existing: SavedPlace?, onSaved: @escaping () -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        let center = existing?.coordinate ??
            CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
        _name = State(initialValue: existing?.label ?? "")
        _kind = State(initialValue: existing?.kind ?? "home")
        _note = State(initialValue: existing?.note ?? "")
        _mapCenter = State(initialValue: center)
        _picked = State(initialValue: existing?.coordinate)
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )))
    }

    var body: some View {
        Form {
            Section("给这个地方起个名字") {
                TextField("例如：家、学校、上海迪士尼", text: $name)
                    .textInputAutocapitalization(.never)
                Picker("类型", selection: $kind) {
                    Text("🏠 家").tag("home")
                    Text("🎓 学校").tag("school")
                    Text("🏰 出游").tag("outing")
                    Text("🚶 适合散步").tag("walk")
                    Text("📍 其他").tag("other")
                }
                TextField("备注（可留空，例如：晚饭后走五分钟）", text: $note)
            }

            Section("在地图上选位置") {
                HStack {
                    TextField("搜索地点，例如：上海迪士尼", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await searchOnMap() } }
                    Button {
                        Task { await searchOnMap() }
                    } label: {
                        if searching { ProgressView() }
                        else { Image(systemName: "magnifyingglass") }
                    }
                    .disabled(searching || searchText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Map(position: $camera)
                    .mapControls { MapCompass(); MapScaleView() }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        mapCenter = context.region.center
                    }
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(LovePalette.accent)
                            .shadow(color: .white, radius: 2)
                            .allowsHitTesting(false)
                    }
                    .frame(height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 13))

                Text("拖动地图，让十字准星落在你想保存的位置，然后点「选用地图中心」。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("选用地图中心") {
                        picked = mapCenter
                        status = "已选好地图中心，点右上角「保存」即可。"
                    }
                    Spacer()
                    Button {
                        locating = true
                        status = "正在获取你现在的位置……"
                        locator.locate()
                    } label: {
                        Label("用当前定位", systemImage: "location.fill")
                    }
                }
                .buttonStyle(.borderless)

                if picked != nil {
                    Label("已选好地点", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Label("尚未选位置，不能保存", systemImage: "mappin.slash")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                if let status {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                Text("仅保存时发送你选定的坐标到私人 VPS，不会将家庭住址写到 GitHub，也不会开启后台定位。适合散步的目的地请选公共、可抵达的地方。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(LovePalette.background)
        .navigationTitle(existing == nil ? "新增秘密地点" : "编辑秘密地点")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if saving { ProgressView() }
                    else { Text("保存") }
                }
                .fontWeight(.semibold)
                .disabled(saving || picked == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onChange(of: locator.location) { _, updated in
            guard locating, let updated else { return }
            locating = false
            guard updated.horizontalAccuracy >= 0,
                  updated.horizontalAccuracy <= 2000,
                  abs(updated.timestamp.timeIntervalSinceNow) <= 60 else {
                status = "定位不够准确或已经过期，再试一次。"
                return
            }
            picked = updated.coordinate
            mapCenter = updated.coordinate
            camera = .region(MKCoordinateRegion(
                center: updated.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            ))
            status = "已选用当前定位。"
        }
        .onChange(of: locator.notice) { _, notice in
            if locating, let notice {
                locating = false
                status = notice
            }
        }
    }

    @MainActor
    private func searchOnMap() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searching = true
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: mapCenter,
                     span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8))
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let coordinate = response.mapItems.first?.placemark.coordinate else {
                status = "没有搜索到地点，试试加上城市名。"
                return
            }
            mapCenter = coordinate
            picked = coordinate
            camera = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            ))
            status = "已选中搜索结果。可拖动地图微调，再点「选用地图中心」。"
        } catch {
            status = "搜索失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func save() async {
        guard let api = session.api, let coordinate = picked else { return }
        saving = true
        defer { saving = false }
        do {
            let payload = SavePlacePayload(
                label: name.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: kind,
                lat: coordinate.latitude,
                lon: coordinate.longitude,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if let existing {
                _ = try await api.updateSavedPlace(id: existing.id, payload: payload)
            } else {
                _ = try await api.createSavedPlace(payload)
            }
            onSaved()
        } catch {
            status = "保存失败：\(error.localizedDescription)"
        }
    }
}
