import SwiftUI

struct CommentsSection: View {
    let serviceId: Int
    let url: String
    @EnvironmentObject private var store: AppStore
    @State private var comments: [CommentItem] = []
    @State private var nextPage: PageToken?
    @State private var error: String?
    @State private var loading = false
    @State private var disabled = false

    var body: some View {
        Group {
            if !store.library.settings.showComments {
                Text("Comments are turned off in Settings").foregroundColor(.secondary)
            } else if disabled {
                Text("Comments are disabled for this video").foregroundColor(.secondary)
            } else if let error {
                StatusView(title: "Could not load comments", message: error) {
                    self.error = nil
                    Task { await loadFirst() }
                }
            } else if comments.isEmpty && !loading {
                Text("No comments").foregroundColor(.secondary)
            } else {
                ForEach(comments) { comment in
                    CommentRow(comment: comment, serviceId: serviceId, url: url)
                }
                if nextPage != nil || loading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .task(id: comments.count) { await loadMore() }
                }
            }
        }
        .task {
            if comments.isEmpty && store.library.settings.showComments { await loadFirst() }
        }
    }

    private func loadFirst() async {
        loading = true
        defer { loading = false }
        do {
            let page = try await Extractor.comments(serviceId: serviceId, url: url)
            disabled = page.disabled == true
            comments = Self.unique(page.items)
            nextPage = page.nextPage
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard let page = nextPage, !loading else { return }
        loading = true
        defer { loading = false }
        guard let more = try? await Extractor.moreComments(serviceId: serviceId, url: url, page: page)
        else {
            nextPage = nil
            return
        }
        comments = Self.unique(comments + more.items)
        nextPage = more.nextPage
    }

    static func unique(_ items: [CommentItem]) -> [CommentItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

struct CommentRow: View {
    let comment: CommentItem
    let serviceId: Int
    let url: String
    @State private var replies: [CommentItem] = []
    @State private var nextReplies: PageToken?
    @State private var repliesOpen = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Thumbnail(url: (comment.uploaderAvatars ?? []).best(minWidth: 48))
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if comment.pinned == true {
                        Image(systemName: "pin.fill").font(.caption2)
                    }
                    Text(comment.uploaderName ?? "").font(.caption.weight(.semibold))
                    Text(comment.textualUploadDate ?? "")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(comment.plainText)
                    .font(.footnote)
                    .textSelection(.enabled)
                HStack(spacing: 12) {
                    if let likes {
                        Label(likes, systemImage: "hand.thumbsup").font(.caption2)
                    }
                    if comment.hearted == true {
                        Image(systemName: "heart.fill").font(.caption2).foregroundColor(.red)
                    }
                    if comment.replies != nil {
                        Button(repliesOpen ? "Hide replies" : replyTitle) { toggleReplies() }
                            .font(.caption2.weight(.semibold))
                            .buttonStyle(.borderless)
                    }
                }
                .foregroundColor(.secondary)
                if repliesOpen {
                    RepliesView(replies: replies)
                    if nextReplies != nil {
                        Button("More replies") {
                            Task { await loadReplies() }
                        }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var likes: String? {
        if let text = comment.textualLikeCount, !text.isEmpty { return text }
        guard let count = comment.likeCount, count > 0 else { return nil }
        return Format.compact(Int64(count))
    }

    private var replyTitle: String {
        guard let count = comment.replyCount, count > 0 else { return "Replies" }
        return count == 1 ? "1 reply" : "\(count) replies"
    }

    private func toggleReplies() {
        repliesOpen.toggle()
        if repliesOpen, replies.isEmpty {
            nextReplies = comment.replies
            Task { await loadReplies() }
        }
    }

    private func loadReplies() async {
        guard let page = nextReplies else { return }
        nextReplies = nil
        guard let more = try? await Extractor.moreComments(serviceId: serviceId, url: url, page: page)
        else { return }
        replies = CommentsSection.unique(replies + more.items)
        nextReplies = more.nextPage
    }
}

/// Replies are one level deep, so they render without the reply controls.
struct RepliesView: View {
    let replies: [CommentItem]

    var body: some View {
        ForEach(replies) { reply in
            VStack(alignment: .leading, spacing: 2) {
                Text(reply.uploaderName ?? "").font(.caption.weight(.semibold))
                Text(reply.plainText).font(.footnote).textSelection(.enabled)
            }
            .padding(.top, 4)
        }
    }
}
