import SwiftUI
import LMSKit

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    @State private var items: [ActivityItem] = []
    @State private var loading = false
    @State private var error: String?
    private var visibleItems: [ActivityItem] {
        items.filter { $0.childID == nil || model.childID == nil || $0.childID == model.childID }
    }
    var body: some View {
        List {
            if let error { ErrorRow(message: error, retry: load) }
            if visibleItems.isEmpty && !loading && error == nil {
                ContentUnavailableView("No updates", systemImage: "bell", description: Text("Updates for your child appear here as SEQTA makes them available."))
            }
            ForEach(visibleItems) { item in
                if let assessment = item.assessment,
                   let child = model.children.first(where: { $0.id == item.childID }) ?? (item.childID == nil ? model.child : nil) {
                    NavigationLink { AssessmentDetailView(assessment: assessment, child: child, releasedAt: item.timestamp) } label: { row(item) }
                } else { row(item) }
            }
        }.listStyle(.plain).navigationTitle("Updates")
            .overlay { if loading { ProgressView("Reading updates…").padding(20).background(.regularMaterial) } }
            .task { await load() }.refreshable { await load() }
    }
    private func row(_ item: ActivityItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let subject = item.assessment?.subject, subject != "Assessment", !subject.isEmpty {
                SubjectPill(subject: subject, context: item.assessment?.displayTitle ?? item.title)
            }
            Text(item.assessment?.displayTitle ?? item.title).font(.headline)
            Text(arrivalDate(item.timestamp)).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 1).listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
    }
    private func arrivalDate(_ text: String) -> String { reportDate(text) }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            let value: [ActivityItem]
            if model.isDemo { value = try Demo.activity() }
            else if let client = model.client, let account = model.accountID {
                value = try await client.activity()
                // Everything in the feed is now in view (switching child only filters it), so none of it is news.
                await UpdateNotifier.shared.didShow(value, account: account)
            }
            else { return }
            try Task.checkCancellation(); items = value
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
