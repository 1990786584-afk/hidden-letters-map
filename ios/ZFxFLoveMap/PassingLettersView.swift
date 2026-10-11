import SwiftUI

// Discovery is not opening. A letter stays unread after the phone passes it.
struct PassingLettersView: View {
    @EnvironmentObject private var session: LoveMapSession
    @EnvironmentObject private var geofences: LetterGeofenceManager
    @State private var letters: [HiddenLetter] = []
    @State private var openedLetter: HiddenLetter?
    @State private var loading = false
    @State private var workingID: String?
    @State private var error: String?

    private var waiting: [HiddenLetter] {
        letters.filter { $0.status == "found" }
    }
    private var opened: [HiddenLetter] {
        letters.filter { $0.status == "opened" }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("那些与你擦肩而过的信 ♡")
                            .font(.system(size: 24, weight: .semibold, design: .serif))
                            .foregroundStyle(LovePalette.accent)
                        Text("有些信，是你经过某个地方时被发现的。它们会一直留在这里，等你想读的时候再拆开。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("后台发现需要在「设置」里主动授权；通知可能延迟，不会精确到秒。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                }
                Section("已发现 · 等你亲手拆封（\(waiting.count)）") {
                    if waiting.isEmpty {
                        Text("还没有待拆的信。今天走过的路，也许会在某天留下惊喜。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(waiting) { letter in
                        Button {
                            Task { await open(letter) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope.badge")
                                    .font(.title2)
                                    .foregroundStyle(LovePalette.accent)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(letter.place ?? "一个熟悉的角落")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(letter.hint)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                if workingID == letter.id { ProgressView() }
                                else { Image(systemName: "heart.fill").foregroundStyle(LovePalette.accent) }
                            }
                            .padding(.vertical, 6)
                        }
                        .disabled(workingID != nil)
                    }
                }
                Section("已经拆开的回忆（\(opened.count)）") {
                    ForEach(opened) { letter in
                        Button {
                            openedLetter = letter
                        } label: {
                            Label(letter.place ?? "旧时来信", systemImage: "heart.text.square")
                                .foregroundStyle(.primary)
                        }
                    }
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LovePalette.background)
            .navigationTitle("擦肩来信 ♡")
            .toolbar {
                Button { Task { await reload() } } label: {
                    if loading { ProgressView() }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(loading)
            }
            .task { await reload() }
            .refreshable { await reload() }
            .onChange(of: geofences.requestedLetterID) { _, id in
                guard id != nil else { return }
                Task { await reload() }
            }
            .sheet(item: $openedLetter) { letter in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            PinkLetter(size: 72).frame(maxWidth: .infinity)
                            Text(letter.place ?? "写给你的信")
                                .font(.title2.bold())
                            Text(letter.hint)
                                .foregroundStyle(.secondary)
                            if let body = letter.body {
                                Text(body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(18)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 18))
                            }
                        }
                        .padding(22)
                    }
                    .background(LovePalette.background)
                    .navigationTitle("终于拆开的信 ♡")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { openedLetter = nil }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func reload() async {
        guard let api = session.api else { return }
        loading = true
        defer { loading = false }
        // If a geofence fired while the phone was locked, reconcile it first.
        await geofences.flushPending()
        do {
            letters = try await api.treasureMap().letters
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func open(_ letter: HiddenLetter) async {
        guard let api = session.api, letter.status == "found" else { return }
        workingID = letter.id
        defer { workingID = nil }
        do {
            openedLetter = try await api.openDiscoveredLetter(letter.id)
            await reload()
        } catch {
            self.error = "拆信失败：\(error.localizedDescription)"
        }
    }
}
