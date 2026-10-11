import SwiftUI

// Native date card UI. All values are read from /api/date-cards and saved back to the same backend.
struct DateCardsView: View {
    @EnvironmentObject private var session: LoveMapSession
    @State private var cards: [DateCard] = []
    @State private var selected: DateCard?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text("ZFxF · LETTERS BETWEEN DATES")
                            .font(.system(size: 11, design: .serif))
                            .tracking(2.0)
                            .foregroundStyle(.secondary)
                        Text("我们的约会来信 ♡")
                            .font(.system(size: 28, weight: .medium, design: .serif))
                        Text("出门前收藏期待，回来后留下真实的感受。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 18)

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }

                    if loading {
                        ProgressView("正在查收我们的信…").padding(38)
                    } else if cards.isEmpty {
                        VStack(spacing: 12) {
                            Text("💌").font(.system(size: 50))
                            Text("还没有收到约会邀请。")
                                .font(.headline)
                            Text("以后我给你开一张邀请函或约会回执，它就会出现在这里。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Text("现在可以先试试藏宝地图和约会照片墙。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(25)
                        .frame(maxWidth: .infinity)
                        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        ForEach(cards) { card in
                            Button {
                                selected = card
                            } label: {
                                DateCardRow(card: card)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 36)
            }
            .background(Color(red: 0.98, green: 0.94, blue: 0.95))
            .navigationTitle("约会来信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button { Task { await refresh() } } label: {
                    if loading { ProgressView() }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(loading)
            }
            .sheet(item: $selected) { card in
                DateCardDetail(card: card) {
                    selected = nil
                    Task { await refresh() }
                }
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
            cards = try await api.dateCards()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct DateCardRow: View {
    let card: DateCard

    var body: some View {
        HStack(spacing: 16) {
            Text(card.kind == "invitation" ? "💌" : "🎀")
                .font(.system(size: 35))
                .frame(width: 54, height: 60)
                .background(Color(red: 0.97, green: 0.91, blue: 0.93),
                            in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(card.kind == "invitation" ? "DATE INVITATION" : "DATE REVIEW")
                    .font(.system(size: 10, weight: .medium, design: .serif))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
                Text(card.title)
                    .font(.system(size: 17, weight: .medium, design: .serif))
                Text(card.date + (card.place.isEmpty ? "" : " · " + card.place))
                    .font(.footnote).foregroundStyle(.secondary)
                Label(card.status == "pending" ? "等待你的回信" : "已经收藏",
                      systemImage: card.status == "pending" ? "envelope" : "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(card.status == "pending" ? .pink : .secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
        .shadow(color: .black.opacity(0.04), radius: 7, y: 3)
    }
}

private struct DateCardDetail: View {
    let card: DateCard
    let onClose: () -> Void

    @EnvironmentObject private var session: LoveMapSession
    @State private var whereTo = ""
    @State private var lookingForward = ""
    @State private var mood = ""
    @State private var needs = ""
    @State private var favorite = ""
    @State private var nextTime = ""
    @State private var note = ""
    @State private var ratings: [String: Double] = [:]
    @State private var saving = false
    @State private var error: String?

    private var isInvitation: Bool { card.kind == "invitation" }
    private var sealed: Bool { card.status != "pending" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(isInvitation ? "💌" : "🎀").font(.system(size: 48))
                            .frame(maxWidth: .infinity)
                        Text(isInvitation ? "DATE INVITATION" : "DATE REVIEW")
                            .font(.system(size: 12, design: .serif)).tracking(2)
                            .foregroundStyle(.secondary)
                        Text(card.title)
                            .font(.system(size: 24, weight: .medium, design: .serif))
                        Text(card.date + (card.place.isEmpty ? "" : " · " + card.place))
                            .font(.footnote).foregroundStyle(.secondary)
                        if !card.intro.isEmpty {
                            Text(card.intro)
                                .font(.body).padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }

                if isInvitation {
                    Section("这一次，你希望……") {
                        DateTextField(label: "最想去哪里", placeholder: "去书店、散步、吃冰淇淋……",
                                      text: $whereTo, limit: 160, locked: sealed)
                        DateTextField(label: "最期待什么", placeholder: "可以慢慢想", text: $lookingForward,
                                      limit: 500, locked: sealed)
                        DateTextField(label: "出门前的心情", placeholder: "开心、紧张、想偷懒……",
                                      text: $mood, limit: 160, locked: sealed)
                        DateTextField(label: "希望我特别注意", placeholder: "例如走累了就找地方坐下",
                                      text: $needs, limit: 800, locked: sealed)
                    }
                } else {
                    Section {
                        Text("这些星星只记录你的真实感受。没有评分也可以提交，想说什么都可以。")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(card.ratings) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(item.title)
                                    Spacer()
                                    Text(ratings[item.key].map { String(format: "%.1f ★", $0) } ?? "未评分")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if ratings[item.key] != nil {
                                    Slider(value: Binding(
                                        get: { ratings[item.key] ?? 3.0 },
                                        set: { ratings[item.key] = $0 }
                                    ), in: 1...5, step: 0.5)
                                    .disabled(sealed)
                                } else if !sealed {
                                    Button("给这一项评分") { ratings[item.key] = 3.0 }
                                        .font(.subheadline)
                                }
                                if !sealed && ratings[item.key] != nil {
                                    Button("清除这项评分") { ratings.removeValue(forKey: item.key) }
                                        .font(.caption)
                                }
                            }.padding(.vertical, 5)
                        }
                    } header: { Text("今天的小回执") }

                    Section("想留下的几句话") {
                        DateTextField(label: "今天最喜欢的一件事", placeholder: "哪怕是很小的事情",
                                      text: $favorite, limit: 800, locked: sealed)
                        DateTextField(label: "下次想怎么约会", placeholder: "不用为了给高分而写好话",
                                      text: $nextTime, limit: 800, locked: sealed)
                        DateTextField(label: "想对 Finnian 说的话", placeholder: "你的原话，会原样保存",
                                      text: $note, limit: 1600, locked: sealed)
                    }
                }

                if sealed {
                    Section {
                        Label("已经封存这张回执", systemImage: "checkmark.seal.fill")
                        if let agentNote = card.agentNote, !agentNote.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Finnian 留下的回信 ♡").font(.headline)
                                Text(agentNote).font(.body)
                            }.padding(.vertical, 7)
                        } else {
                            Text("已经保存到私人服务器。等 Finnian 收到回执、写完复盘后，刷新即可看到。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        Button {
                            Task { await submit() }
                        } label: {
                            HStack {
                                Spacer()
                                if saving { ProgressView() }
                                else { Text(isInvitation ? "接受约会邀请 💌" : "封存今天的回忆 ♡").bold() }
                                Spacer()
                            }
                        }
                        .disabled(saving)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.98, green: 0.94, blue: 0.95))
            .navigationTitle(isInvitation ? "约会邀请函" : "约会回执")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { onClose() } }
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        guard let answers = card.answers else { return }
        whereTo = answers.whereTo ?? ""
        lookingForward = answers.lookingForward ?? ""
        mood = answers.mood ?? ""
        needs = answers.needs ?? ""
        ratings = answers.ratings ?? [:]
        favorite = answers.favorite ?? ""
        nextTime = answers.nextTime ?? ""
        note = answers.note ?? ""
    }

    @MainActor
    private func submit() async {
        guard let api = session.api else { return }
        saving = true
        error = nil
        defer { saving = false }
        let answers = DateCardAnswers(
            whereTo: isInvitation ? whereTo : nil,
            lookingForward: isInvitation ? lookingForward : nil,
            mood: isInvitation ? mood : nil,
            needs: isInvitation ? needs : nil,
            ratings: isInvitation ? nil : ratings,
            favorite: isInvitation ? nil : favorite,
            nextTime: isInvitation ? nil : nextTime,
            note: isInvitation ? nil : note)
        do {
            _ = try await api.submitDateCard(id: card.id, answers: answers)
            onClose()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct DateTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let limit: Int
    let locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.subheadline.weight(.medium))
            if locked {
                Text(text.isEmpty ? "（没有填写）" : text)
                    .font(.body)
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(2...6)
                    .onChange(of: text) { _, latest in
                        if latest.count > limit { text = String(latest.prefix(limit)) }
                    }
            }
        }
        .padding(.vertical, 6)
    }
}
