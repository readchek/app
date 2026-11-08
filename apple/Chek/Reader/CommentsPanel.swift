import SwiftUI

/// The comments button in the reader's top bar, with how many there are.
/// A site that gives only a count opens its own thread instead.
struct CommentsButton: View {
    let comments: ChapterComments
    let show: () -> Void

    var body: some View {
        if comments.hasList {
            Button(action: show) { label }
        } else if let thread = comments.thread {
            Link(destination: thread) { label }
        }
    }

    private var label: some View {
        Label {
            Text("^[\(comments.count ?? 0) comment](inflect: true)")
        } icon: {
            Image(systemName: "bubble")
        }
    }
}

/// Readers' comments on a chapter, from its site and read-only: in the
/// site's orders, with replies on request, spoilers covered until tapped,
/// and a menu on each to hide its author or report it on the site.
struct CommentsPanel: View {
    let comments: ChapterComments
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text("Comments")
                                .font(.headline)
                            if let count = comments.count {
                                Text("\(count) on \(comments.site)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if comments.orders.count > 1 {
                        ToolbarItem(placement: .topBarLeading) {
                            OrderMenu(comments: comments)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", role: .confirm) {
                            dismiss()
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if comments.phase != .loading, let thread = comments.thread {
                        ThreadFooter(site: comments.site, thread: thread)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // At the medium height the sheet's glass picks up the page behind
        // it, so the bar took on the page's colour while the list stayed
        // plain. Comments are text to read, so the whole sheet is solid.
        .presentationBackground(.background)
        .task {
            await comments.loadIfNeeded()
        }
    }

    @ViewBuilder private var content: some View {
        switch comments.phase {
        case .idle, .loading:
            LoadingState()
        case .failed(let error):
            FailureState(error: error) {
                await comments.load()
            }
        case .loaded, .loadingMore:
            if comments.items.isEmpty {
                ContentUnavailableView("No Comments Yet", systemImage: "bubble", description: Text("Comments people leave on \(comments.site) show here."))
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            ForEach(comments.items) { comment in
                CommentThread(comment: comment, comments: comments)
                    .onAppear {
                        if comment.id == comments.items.last?.id {
                            Task { await comments.loadMore() }
                        }
                    }
            }
            if comments.phase == .loadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            } else if comments.moreFailed {
                Button("Couldn't load more. Try Again", systemImage: "arrow.clockwise") {
                    Task { await comments.loadMore() }
                }
                .font(.subheadline)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }
}

/// Picks the order, from those the site offers.
private struct OrderMenu: View {
    let comments: ChapterComments

    var body: some View {
        Menu {
            Picker("Order", selection: Binding(
                get: { comments.order ?? .top },
                set: { order in Task { await comments.choose(order) } }
            )) {
                ForEach(comments.orders, id: \.self) { order in
                    Text(order.title).tag(order)
                }
            }
        } label: {
            // A toolbar draws a Label as its icon alone, which left a bare
            // chevron, so the order's name is spelled out beside it.
            HStack(spacing: 4) {
                Text((comments.order ?? .top).title)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .fontWeight(.semibold)
            }
        }
        .accessibilityLabel(Text("Order"))
        .accessibilityValue(Text((comments.order ?? .top).title))
    }
}

/// Where the comments come from, with the thread on the site.
private struct ThreadFooter: View {
    let site: String
    let thread: URL

    var body: some View {
        HStack {
            Text("From \(site) · Read-only")
                .foregroundStyle(.secondary)
            Spacer()
            Link(destination: thread) {
                Label("Open Thread", systemImage: "arrow.up.right")
                    .labelStyle(.titleAndIcon)
            }
        }
        .font(.footnote)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// A top-level comment and, once asked for, its replies.
private struct CommentThread: View {
    let comment: ChekAPI.Comment
    let comments: ChapterComments
    @Environment(ReaderSettings.self) private var settings

    private var isHidden: Bool {
        settings.isHidden(comment.author.name, on: comments.chapter.source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CommentRow(comment: comment, comments: comments) {
                // Hiding someone folds their whole thread into one line, so
                // the replies button and the replies go with the comment.
                if comment.replyCount > 0, !isHidden {
                    Button {
                        if isOpen {
                            comments.closeReplies(of: comment)
                        } else {
                            Task { await comments.loadReplies(of: comment) }
                        }
                    } label: {
                        if isOpen {
                            Text("Hide Replies")
                        } else {
                            Text("^[\(comment.replyCount) reply](inflect: true)")
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            if !isHidden, let replies = comments.replies[comment.id] {
                Group {
                    switch replies {
                    case .loading:
                        ProgressView()
                    case .failed:
                        Button("Couldn't load the replies. Try Again") {
                            Task { await comments.loadReplies(of: comment) }
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                    case .loaded(let items, let next):
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(items) { reply in
                                CommentRow(comment: reply, comments: comments) { EmptyView() }
                                if reply.id != items.last?.id {
                                    Divider()
                                }
                            }
                            if next != nil {
                                Button("More Replies") {
                                    Task { await comments.loadReplies(of: comment) }
                                }
                                .buttonStyle(.borderless)
                                .font(.subheadline)
                            }
                        }
                    }
                }
                .padding(.leading, 28)
            }
        }
        .padding(.vertical, 6)
    }

    private var isOpen: Bool {
        comments.replies[comment.id] != nil
    }
}

/// One comment: who wrote it and when, its text, its score and what
/// `extra` adds, such as its replies button. A hidden author's comment is
/// one line, with a way to show them again.
private struct CommentRow<Extra: View>: View {
    let comment: ChekAPI.Comment
    let comments: ChapterComments
    @ViewBuilder let extra: () -> Extra
    @Environment(ReaderSettings.self) private var settings
    /// Spoilers tapped open, by their run's place; the whole comment's is -1.
    @State private var revealed: Set<Int> = []

    private var source: String { comments.chapter.source }

    var body: some View {
        if settings.isHidden(comment.author.name, on: source) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("Comments from \(comment.author.name) hidden ·")
                        .foregroundStyle(.secondary)
                    Button("Show") {
                        settings.setHidden(false, comment.author.name, on: source)
                    }
                    .buttonStyle(.borderless)
                }
                .font(.footnote)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                CommentAvatar(author: comment.author, server: comments.chapter.server)
                details
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                header
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                // A long name or badge used to wrap the time in the middle
                // ("5" on one line, "hr ago" on the next). The time is kept
                // whole, and the name gives way instead.
                if let when {
                    when
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .layoutPriority(1)
                }
                CommentMenu(comment: comment, comments: comments)
            }
            text
            if !comment.images.isEmpty, !(comment.spoiler && !revealed.contains(-1)) {
                CommentImages(paths: comment.images, server: comments.chapter.server)
            }
            HStack(spacing: 16) {
                if let score = comment.score {
                    Label {
                        Text(score, format: .number)
                    } icon: {
                        Image(systemName: "arrowtriangle.up.fill")
                            .imageScale(.small)
                    }
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Score \(score)"))
                }
                extra()
            }
            .font(.subheadline)
        }
    }

    /// Who wrote it, with their badge and who they answered.
    private var header: some View {
        var line = Text(comment.author.name).fontWeight(.semibold)
        if let badge = comment.author.badge, !badge.isEmpty {
            line = line + Text(" · \(badge)").foregroundStyle(.secondary)
        }
        if let replyTo = comment.replyTo {
            line = line + Text(" · ").foregroundStyle(.secondary) + Text("to \(replyTo)").foregroundStyle(.secondary)
        }
        return line
            .font(.subheadline)
    }

    /// When it was written, and that it was edited since.
    private var when: Text? {
        var parts: [Text] = []
        if let date = comment.publishedDate {
            parts.append(Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow)))
        }
        if comment.edited {
            parts.append(Text("Edited"))
        }
        guard var line = parts.first else { return nil }
        for part in parts.dropFirst() {
            line = line + Text(" · ") + part
        }
        return line
    }

    @ViewBuilder private var text: some View {
        if comment.spoiler && !revealed.contains(-1) {
            // An opaque block that is the button, never a blur, so nothing
            // of the text shows through.
            Button {
                revealed.insert(-1)
            } label: {
                Text("Spoiler · Tap to Show")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.quaternary, in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        } else {
            Text(styled(comment.body))
                .font(.body)
                .textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    // A covered spoiler is a link to itself.
                    if url.scheme == Self.spoilerScheme, let index = Int(url.host() ?? "") {
                        revealed.insert(index)
                        return .handled
                    }
                    return .systemAction
                })
        }
    }

    private static var spoilerScheme: String { "chek-spoiler" }

    /// The runs as one styled text. A covered spoiler shows only a fixed
    /// "Spoiler" in its place, so its text isn't there until it's tapped.
    private func styled(_ runs: [ChekAPI.CommentRun]) -> AttributedString {
        var text = AttributedString()
        for (index, run) in runs.enumerated() {
            if run.spoiler == true && !revealed.contains(index) {
                var cover = AttributedString(String(localized: "Spoiler"))
                cover.foregroundColor = Color.secondary
                cover.backgroundColor = Color(uiColor: .tertiarySystemFill)
                cover.link = URL(string: "\(Self.spoilerScheme)://\(index)")
                text += AttributedString(" ") + cover + AttributedString(" ")
                continue
            }
            var part = AttributedString(run.text)
            var intent: InlinePresentationIntent = []
            if run.bold == true { intent.insert(.stronglyEmphasized) }
            if run.italic == true || run.quote == true { intent.insert(.emphasized) }
            if run.strike == true { intent.insert(.strikethrough) }
            if run.code == true { intent.insert(.code) }
            part.inlinePresentationIntent = intent.isEmpty ? nil : intent
            if run.quote == true {
                part.foregroundColor = Color.secondary
            }
            if let link = run.link.flatMap(ChapterComments.safeLink) {
                part.link = link
            }
            text += part
        }
        return text
    }
}

/// What can be done with a comment: hide its author, or report it or
/// read it on its site, which is where reports go.
private struct CommentMenu: View {
    let comment: ChekAPI.Comment
    let comments: ChapterComments
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        Menu {
            Button("Hide Comments from \(comment.author.name)", systemImage: "eye.slash") {
                settings.setHidden(true, comment.author.name, on: comments.chapter.source, siteName: comments.site)
            }
            if let url = comment.url.flatMap(ChapterComments.safeLink) {
                Link(destination: url) {
                    Label("Report on \(comments.site)", systemImage: "flag")
                }
                Link(destination: url) {
                    Label("Open on \(comments.site)", systemImage: "arrow.up.right")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("More for \(comment.author.name)'s comment"))
    }
}

/// The commenter's picture from the site, fetched through the server, or
/// their initial while it loads or when the site has none.
private struct CommentAvatar: View {
    let author: ChekAPI.CommentAuthor
    let server: UUID
    @Environment(ServerStore.self) private var servers
    @State private var image: UIImage?

    private var key: String? {
        author.avatarUrl.map { "avatar:\(server):\($0)" }
    }

    var body: some View {
        Group {
            if let image = image ?? key.flatMap({ ImagePipeline.shared.cachedImage(for: $0) }) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(author.name.prefix(1).uppercased())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(.circle)
        .accessibilityHidden(true)
        .task(id: key) {
            guard let key, let path = author.avatarUrl,
                  let client = servers.client(for: server),
                  let request = client.imageRequest(path)
            else { return }
            let session = client.session
            image = await ImagePipeline.shared.image(for: key) {
                guard let answer = try? await session.data(for: request) else { return nil }
                return await ImagePipeline.decode(answer.0)
            }
        }
    }
}

/// Pictures attached to a comment, fetched through the server.
private struct CommentImages: View {
    let paths: [String]
    let server: UUID
    @Environment(ServerStore.self) private var servers
    @State private var images: [Int: UIImage] = [:]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(paths.indices, id: \.self) { index in
                    Group {
                        if let image = images[index] {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(.rect(cornerRadius: 8))
                    .accessibilityLabel(Text("Picture"))
                }
            }
        }
        .scrollIndicators(.hidden)
        .task {
            guard let client = servers.client(for: server) else { return }
            for (index, path) in paths.enumerated() {
                guard let request = client.imageRequest(path),
                      let answer = try? await client.session.data(for: request),
                      let image = await ImagePipeline.decode(answer.0)
                else { continue }
                images[index] = image
            }
        }
    }
}

/// Everyone whose comments you've hidden, by site, with a swipe to show
/// them again.
struct HiddenCommentersView: View {
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        List {
            if settings.hiddenCommenters.isEmpty {
                ContentUnavailableView("No Hidden Commenters", systemImage: "eye.slash", description: Text("Hide someone from a comment's menu, and they're listed here."))
                    .listRowBackground(Color.clear)
            }
            ForEach(settings.hiddenCommenters.keys.sorted(), id: \.self) { site in
                Section {
                    ForEach(settings.hiddenCommenters[site] ?? [], id: \.self) { name in
                        Text(name)
                            .swipeActions {
                                Button("Show") {
                                    settings.setHidden(false, name, on: site)
                                }
                            }
                    }
                } header: {
                    Text(settings.commentSites[site] ?? site)
                }
            }
        }
        .navigationTitle("Hidden Commenters")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !settings.hiddenCommenters.isEmpty {
                Text("Their comments stay hidden on this device. Swipe to show them again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}

extension ChekAPI.CommentOrder {
    var title: LocalizedStringResource {
        switch self {
        case .top: "Top"
        case .newest: "Newest"
        case .oldest: "Oldest"
        }
    }
}
