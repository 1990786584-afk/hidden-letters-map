import SwiftUI
import PhotosUI
import UIKit

struct DateBoardView: View {
    @EnvironmentObject private var session: LoveMapSession
    @State private var memories: [DateMemory] = []
    @State private var selected: DateMemory?
    @State private var creating = false
    @State private var loading = false
    @State private var error: String?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 19) {
                    VStack(spacing: 7) {
                        Text("ZFxF · OUR LITTLE DATES")
                            .font(.system(size: 11, design: .serif))
                            .tracking(2.5).foregroundStyle(.secondary)
                        Text("我们的约会板 ♡")
                            .font(.system(size: 28, weight: .medium, design: .serif))
                        Text("照片与小日记，收藏每一个普通又特别的日子。")
                            .font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 19)
                    if let error {
                        Text(error)
                            .font(.footnote).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    HStack {
                        Text("\(memories.count) 个约会纪念")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            creating = true
                        } label: { Label("记录约会", systemImage: "plus") }
                            .buttonStyle(.borderedProminent)
                    }
                    if loading {
                        ProgressView("正在打开我们的纪念册…").padding(50)
                    } else if memories.isEmpty {
                        VStack(spacing: 12) {
                            Text("📷").font(.system(size: 48))
                            Text("第一张拍立得，等你来贴。")
                                .font(.headline)
                            Text("点击「记录约会」，上传今天的照片和心情。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 65)
                        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(memories) { memory in
                                Button {
                                    selected = memory
                                } label: {
                                    DatePostcard(memory: memory)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 45)
            }
            .background(LovePalette.background)
            .navigationTitle("约会纪念册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") } }
            .sheet(isPresented: $creating) {
                NewDateView {
                    creating = false
                    Task { await refresh() }
                }
            }
            .sheet(item: $selected) { memory in
                DateDetailView(memory: memory)
            }
        }
        .task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        guard let api = session.api else { return }
        loading = true
        defer { loading = false }
        do {
            memories = try await api.dates()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct AuthenticatedPhoto: View {
    @EnvironmentObject private var session: LoveMapSession
    let filename: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(LovePalette.blush)
                    .overlay { ProgressView().tint(LovePalette.accent) }
            }
        }
        .clipped()
        .task(id: filename) {
            guard let api = session.api else { return }
            image = try? await api.photo(named: filename)
        }
    }
}

struct DatePostcard: View {
    let memory: DateMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Group {
                if let name = memory.photos.first {
                    AuthenticatedPhoto(filename: name)
                } else {
                    Rectangle().fill(LovePalette.blush)
                        .overlay { Text("♡").font(.system(size: 58, design: .serif)).foregroundStyle(LovePalette.accent.opacity(0.65)) }
                }
            }
            .frame(height: 145)
            .clipped()
            Text(memory.date.replacingOccurrences(of: "-", with: " · "))
                .font(.system(size: 10, design: .serif)).foregroundStyle(.secondary)
            Text(memory.title)
                .font(.system(size: 15, weight: .medium, design: .serif))
                .lineLimit(2)
            if !memory.place.isEmpty {
                Label(memory.place, systemImage: "mappin")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

struct DateDetailView: View {
    let memory: DateMemory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    Text(memory.date).font(.subheadline).foregroundStyle(.secondary)
                    Text(memory.title).font(.system(size: 28, weight: .medium, design: .serif))
                    if !memory.place.isEmpty {
                        Label(memory.place, systemImage: "mappin")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(memory.photos, id: \.self) { filename in
                        AuthenticatedPhoto(filename: filename)
                            .frame(maxWidth: .infinity)
                            .frame(height: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                    }
                    if !memory.note.isEmpty {
                        Text(memory.note)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(19)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(20)
            }
            .background(LovePalette.background)
            .navigationTitle("这一天 ♡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
        }
    }
}

struct NewDateView: View {
    @EnvironmentObject private var session: LoveMapSession
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void

    @State private var title = ""
    @State private var date = Date()
    @State private var place = ""
    @State private var note = ""
    @State private var chosenPhotos: [PhotosPickerItem] = []
    @State private var photos: [UIImage] = []
    @State private var saving = false
    @State private var processing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("我们的约会") {
                    TextField("约会标题", text: $title)
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("去过哪里", text: $place)
                    TextField("今天的小日记", text: $note, axis: .vertical)
                        .lineLimit(3...7)
                }
                Section("拍立得相册 · 最多 4 张") {
                    PhotosPicker(selection: $chosenPhotos, maxSelectionCount: 4, matching: .images) {
                        Label("从相册挑照片", systemImage: "photo.on.rectangle")
                    }
                    if processing { ProgressView("正在读取照片…") }
                    if !photos.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 9) {
                                ForEach(photos.indices, id: \.self) { index in
                                    Image(uiImage: photos[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 90, height: 90)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 7))
                                }
                            }
                        }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Spacer()
                            if saving { ProgressView() }
                            else { Text("收藏这一天 ♡").bold() }
                            Spacer()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving || processing)
                }
            }
            .navigationTitle("新的约会纪念")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
            }
            .onChange(of: chosenPhotos) { _, newValue in
                Task { await loadPhotos(newValue) }
            }
        }
    }

    @MainActor
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        processing = true
        defer { processing = false }
        error = nil
        var images: [UIImage] = []
        for item in items.prefix(4) {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        photos = images
        if images.count != items.count { error = "有照片没能读取，可以重新选择。" }
    }

    @MainActor
    private func save() async {
        guard let api = session.api else { return }
        saving = true
        defer { saving = false }
        error = nil
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let payload = NewDatePayload(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                date: formatter.string(from: date),
                place: place,
                note: note,
                photos: try photos.map { try encodePhoto($0) }
            )
            _ = try await api.addDate(payload)
            onSaved()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func encodePhoto(_ image: UIImage) throws -> String {
        let maxEdge: CGFloat = 1200
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: max(1, round(size.width * scale)),
                            height: max(1, round(size.height * scale)))
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        for quality: CGFloat in [0.75, 0.6, 0.45] {
            if let data = resized.jpegData(compressionQuality: quality),
               data.count <= 1_500_000 {
                return "data:image/jpeg;base64," + data.base64EncodedString()
            }
        }
        throw LoveMapError.server("这张照片压缩后还是太大，换一张试试。")
    }
}
