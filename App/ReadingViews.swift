import SwiftUI
import LMSKit
import PDFKit

struct NewsView: View {
    var close: (() -> Void)? = nil
    @EnvironmentObject private var model: AppModel
    @State private var date = Date()
    @State private var notices: [Notice] = []
    @State private var loadedDate: Date?
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                DatePicker("News for", selection: $date, displayedComponents: .date)
            } footer: {
                // Only worth saying when switching child wouldn't change the news.
                if model.children.count > 1 { Text("School notices are shared across your account’s children.") }
            }

            if let error { ErrorRow(message: error, retry: { await load() }) }
            if notices.isEmpty && !loading && error == nil {
                ContentUnavailableView("A quiet day", systemImage: "newspaper", description: Text("No notices were published for this date. Try another day."))
            }
            ForEach(notices) { notice in
                let readScope = model.newsScope
                // Notices carry no date of their own: this is the day they're listed under.
                let byline = [notice.author, loadedDate.map(longDate)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                NavigationLink {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(notice.label.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.teal)
                            Text(notice.title).font(.largeTitle.weight(.bold))
                            Text(byline).font(.subheadline).foregroundStyle(.secondary)
                            ReadingRule()
                            ReadableHTML(html: notice.html)
                        }.padding(24).frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
                    }.navigationTitle("News").navigationBarTitleDisplayMode(.inline)
                        .onAppear { model.markNewsRead(notice.id, scope: readScope) }
                        .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(notice.label.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.teal)
                        HStack {
                            Text(notice.title).font(.headline).foregroundStyle(.primary)
                            if model.isNewsUnread(notice.id) {
                                Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.teal).accessibilityLabel("Unread")
                            }
                        }
                        Text(byline).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 10)
                }
            }
        }.listStyle(.plain).overlay { if loading { ProgressView("Reading school news…").padding(20).background(.regularMaterial) } }.navigationTitle("News")
            .toolbar { if let close { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close) } } }
            // Returning from a notice re-runs this task; only reload when the date has changed, keeping the position.
            .task(id: date) { if loadedDate != date { await load() } }
            .refreshable { await model.client?.clearCache(); await load(refreshing: true) }
    }
    private func load(refreshing: Bool = false) async {
        let shown = date, scope = model.newsScope
        loading = true; error = nil; if !refreshing { notices = [] }
        defer { loading = false }
        do {
            let values: [Notice]
            if model.isDemo { values = try Demo.notices() }
            else if let client = model.client { values = try await client.news(on: date) }
            else { return }
            try Task.checkCancellation()
            guard scope == model.newsScope, shown == date else { return }
            notices = values; loadedDate = shown; model.recordNews(values, on: shown)
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct AssessmentsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var upcoming: [Assessment] = []
    @State private var past: [Assessment] = []
    @State private var courses: [Course] = []
    @State private var courseID: String?
    /// Results, Upcoming or Reports. Reports live here (their own tab made room for Lunch).
    @State private var pane = AssessmentPane.results
    private var showingPast: Bool { pane == .results }
    /// What's on screen, so returning from an assessment (which re-runs the tasks below) doesn't reload and lose the
    /// scroll position. Reloads happen only when the child, Results/Upcoming or subject actually changes.
    @State private var loadedCoursesFor: String?
    @State private var loadedListKey: String?
    private var listKey: String { "\(model.childID ?? "")-\(showingPast)-\(courseID ?? "")" }
    @State private var loading = false
    @State private var error: String?
    // Sorting and filtering, remembered separately for Results and Upcoming.
    @AppStorage("assessmentResultsSort") private var resultsSort = AssessmentSort.newestFirst
    @AppStorage("assessmentUpcomingSort") private var upcomingSort = AssessmentSort.oldestFirst
    @AppStorage("assessmentResultsShow") private var resultsShow = AssessmentShow.all
    @AppStorage("assessmentUpcomingShow") private var upcomingShow = AssessmentShow.all
    @AppStorage(AssessmentMark.hideKey) private var hideMarks = false
    /// Upcoming has no per-subject request, so its subject filter works on the loaded list.
    @State private var upcomingSubject: String?
    @State private var search = ""
    private var sortChoice: Binding<AssessmentSort> { showingPast ? $resultsSort : $upcomingSort }
    private var showChoice: Binding<AssessmentShow> { showingPast ? $resultsShow : $upcomingShow }
    /// Ordering by mark would give hidden marks away, so it falls back to the default while they're hidden.
    private var sort: AssessmentSort {
        let chosen = sortChoice.wrappedValue
        return hideMarks && chosen.usesMarks ? (showingPast ? .newestFirst : .oldestFirst) : chosen
    }
    private var sortOptions: [(AssessmentSort, String)] {
        showingPast
            ? [(.newestFirst, "Newest first"), (.oldestFirst, "Oldest first"), (.subject, "Subject")]
                + (hideMarks ? [] : [(.highestMark, "Highest mark"), (.lowestMark, "Lowest mark")])
            : [(.oldestFirst, "Due soonest"), (.newestFirst, "Due latest"), (.subject, "Subject")]
    }
    private var showOptions: [(AssessmentShow, String)] {
        showingPast ? [(.all, "All"), (.marked, "With a mark"), (.feedback, "With feedback"), (.awaiting, "Awaiting results")]
            : [(.all, "All"), (.overdue, "Overdue")]
    }
    private var upcomingSubjects: [String] { Array(Set(upcoming.map(\.subject))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
    /// Whether anything is narrowing or reordering the list from its default.
    private var customised: Bool {
        sort != (showingPast ? .newestFirst : .oldestFirst) || showChoice.wrappedValue != .all || (!showingPast && upcomingSubject != nil)
    }
    private func resetFilters() {
        sortChoice.wrappedValue = showingPast ? .newestFirst : .oldestFirst; showChoice.wrappedValue = .all
        upcomingSubject = nil; search = ""
    }
    var body: some View {
        if pane == .reports { ReportsView(pane: $pane) } else { assessmentList }
    }
    private var assessmentList: some View {
        List {
            if let child = model.child {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        AssessmentPanePicker(pane: $pane)
                        HStack(spacing: 4) {
                            if showingPast {
                                Picker("Subject", selection: $courseID) {
                                    Text("All").tag(String?.none)
                                    ForEach(courses) { course in Text("\(course.title) · \(course.term)").tag(Optional(course.id)) }
                                }.frame(maxWidth: .infinity, minHeight: 44)
                                    .accessibilityIdentifier("assessment-subject-filter")
                                    .padding(.horizontal, 10)
                                    .contentShape(Rectangle())
                            } else {
                                Picker("Subject", selection: $upcomingSubject) {
                                    Text("All").tag(String?.none)
                                    ForEach(upcomingSubjects, id: \.self) { Text($0).tag(Optional($0)) }
                                }.frame(maxWidth: .infinity, minHeight: 44)
                                    .padding(.horizontal, 10)
                                    .contentShape(Rectangle())
                            }
                            sortAndFilterMenu
                        }
                    }.padding(.vertical, 3)
                }
                if let error { ErrorRow(message: error, retry: { await load() }) }
                let loaded = showingPast ? past : upcoming
                let items = AssessmentListing.arrange(loaded, sort: sort, show: showChoice.wrappedValue,
                                                      subject: showingPast ? nil : upcomingSubject, search: search)
                if loaded.isEmpty && !loading && error == nil {
                    ContentUnavailableView(showingPast ? "No results to show" : "All clear for now", systemImage: "checklist", description: Text(showingPast ? "No released results or feedback are available for this selection." : "There are no upcoming assessments for this child."))
                } else if items.isEmpty && !loading && error == nil {
                    ContentUnavailableView {
                        Label("No matching assessments", systemImage: "line.3.horizontal.decrease.circle")
                    } description: { Text("Nothing here matches the filter or search.") } actions: {
                        Button("Show all") { resetFilters() }
                    }
                }
                ForEach(items) { assessment in
                    NavigationLink {
                        AssessmentDetailView(assessment: assessment, child: child)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                SubjectPill(subject: assessment.subject, context: assessment.displayTitle)
                                Spacer(minLength: 8)
                                AssessmentMark(assessment: assessment)
                            }
                            Text(assessment.displayTitle).font(.headline).lineLimit(2)
                            HStack(spacing: 10) {
                                if !assessment.due.isEmpty { Text(reportDate(assessment.due)) }
                                // A released mark or feedback already shows on the right (the mark, or the feedback bubble).
                                if !assessment.status.isEmpty, !["MARKS_RELEASED", "FEEDBACK_RELEASED"].contains(assessment.status) {
                                    Text(assessment.statusLabel)
                                }
                            }.font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 1)
                            .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                    }
                }
            } else { ChildPlaceholder() }
        }.listStyle(.plain).overlay { if loading { ProgressView("Reading assessments…").padding(20).background(.regularMaterial) } }.navigationTitle("Assessments").task(id: model.childID) { await initialLoad() }
            .searchable(text: $search, prompt: "Search assessments")
            .task(id: "\(showingPast)-\(courseID ?? "")") {
                guard loadedListKey != listKey else { return }
                if showingPast { if !courses.isEmpty { await loadPast() } } else { await loadUpcoming() }
            }
            .refreshable { await model.client?.clearCache(); await load(refreshing: true) }
    }
    /// Sort order and which assessments show, beside the subject filter; filled in when they differ from the default.
    private var sortAndFilterMenu: some View {
        Menu {
            Picker("Sort by", selection: sortChoice) { ForEach(sortOptions, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.inline)
            Picker("Show", selection: showChoice) { ForEach(showOptions, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.inline)
            if customised { Button("Reset to default", systemImage: "arrow.counterclockwise") { resetFilters() } }
        } label: {
            Image(systemName: customised ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.title3).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Sort and filter")
        .accessibilityValue([sortOptions.first { $0.0 == sort }?.1, showOptions.first { $0.0 == showChoice.wrappedValue }?.1]
            .compactMap { $0 }.joined(separator: ", "))
    }
    private func initialLoad() async {
        guard let child = model.child, loadedCoursesFor != child.id else { return }
        // This task runs again when returning from a detail page. Keep the current
        // selection and courses until refreshed; changing child/account recreates this view.
        loading = true; error = nil
        defer { loading = false }
        do {
            if model.isDemo {
                upcoming = try Demo.assessments(child: child); courses = try Demo.courses()
            } else if let client = model.client {
                let list = try await client.courses(for: child)
                try Task.checkCancellation(); courses = list.sorted { $0.active && !$1.active }
            }
            if let selected = courseID, !courses.contains(where: { $0.id == selected }) {
                courseID = nil
            }
            loadedCoursesFor = child.id
            await load()
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func loadUpcoming(refreshing: Bool = false) async {
        guard let child = model.child else { return }
        let key = listKey
        // A refresh keeps the current list (and position) on screen until the new one arrives.
        loading = true; error = nil; if !refreshing { upcoming = [] }
        defer { loading = false }
        do {
            let values: [Assessment]
            if model.isDemo { values = try Demo.assessments(child: child) }
            else if let client = model.client { values = try await client.upcomingAssessments(for: child) }
            else { return }
            try Task.checkCancellation(); upcoming = values; loadedListKey = key
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func loadPast(refreshing: Bool = false) async {
        guard let child = model.child else { return }
        let course = courses.first(where: { $0.id == courseID })
        let selected = courseID, key = listKey
        loading = true; error = nil; if !refreshing { past = [] }
        defer { if selected == courseID { loading = false } }
        do {
            let values: [Assessment]
            if model.isDemo { values = try Demo.results() }
            else if let client = model.client {
                if let course { values = try await client.pastAssessments(for: child, course: course) }
                else { values = try await client.allPastAssessments(for: child) }
            }
            else { return }
            try Task.checkCancellation(); guard selected == courseID else { return }; past = values.sorted { $0.due > $1.due }; loadedListKey = key
        } catch is CancellationError { }
        catch { if !Task.isCancelled && selected == courseID { self.error = error.localizedDescription } }
    }
    private func load(refreshing: Bool = false) async {
        if showingPast { await loadPast(refreshing: refreshing) } else { await loadUpcoming(refreshing: refreshing) }
    }
}

struct AssessmentDetailView: View {
    @EnvironmentObject private var model: AppModel
    let assessment: Assessment
    let child: Child
    /// When the assessment was opened from an update, the update's timestamp: the last-resort date for the header.
    var releasedAt: String? = nil
    @State private var details: JSONValue?
    /// The due date found by looking this assessment up in SEQTA's lists, when it was opened without one (from an update).
    @State private var listedDue: String?
    /// Always show a date: the due date (carried in, or looked up from the assessment lists, since `assessment/get` has
    /// no dates), otherwise the update's own date, exactly as the Updates list shows it.
    private var headerDate: String? {
        let due = [assessment.due, listedDue ?? ""].first { !$0.isEmpty }
        if let due { return reportDate(due) }
        if let releasedAt, !releasedAt.isEmpty { return reportDate(releasedAt) }
        return nil
    }
    @State private var attachments: [AssessmentAttachment] = []
    @State private var error: String?
    @State private var attachmentError: String?
    @State private var loading = false
    @State private var loadingAttachments = false
    @State private var preparingPrint = false
    @State private var overviewExpanded = false
    @State private var rotatedMedia: [String: Data] = [:]
    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section {
                // A plain row, not a section header: plain lists pin headers over the content scrolling beneath.
                HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    // Same order as the assessments list: subject, title, date.
                    SubjectPill(subject: assessment.subject, context: assessment.displayTitle)
                    Text(assessment.displayTitle).readingStyle(.title)
                        .fixedSize(horizontal: false, vertical: true)
                    if let headerDate { Text(headerDate).readingStyle(.meta) }
                    if let teacher = model.teacher(forClass: assessment.metaclass, child: child) {
                        // The email is a bonus: link the name only when there's an address and something here can send
                        // mail (the Simulator, and phones without a mail app, can't), so the envelope never promises a dead tap.
                        if let mail = URL(string: "mailto:" + teacher.email), !teacher.email.isEmpty, UIApplication.shared.canOpenURL(mail) {
                            // Not a Label: inside a list row that spaces the icon like a row icon, far from the name.
                            Link(destination: mail) {
                                HStack(spacing: 5) { Image(systemName: "envelope").imageScale(.small); Text(teacher.name) }
                            }.font(.footnote).foregroundStyle(.tint).accessibilityLabel(teacher.name).accessibilityHint("Emails \(teacher.name)")
                        } else {
                            Text(teacher.name).readingStyle(.meta)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    if !attachments.isEmpty {
                        AttachmentStack(attachments: attachments, rotated: rotatedMedia) {
                            withAnimation(.smooth(duration: 0.5)) { proxy.scrollTo("assessment-files", anchor: .top) }
                        }.padding(.top, 4).transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }.textCase(nil)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: attachments.isEmpty)
                    .padding(.bottom, 4)
                    .listRowSeparator(.hidden)
            }.listSectionSeparator(.hidden)

                if let error { ErrorRow(message: error, retry: { await load() }) }
                if let details {
                    if let description = details["description"].string, !ReadableHTML.plainText(from: description).isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                if overviewExpanded {
                                    FeedbackView(html: description)
                                } else {
                                    ReadableHTML(html: description).lineLimit(3)
                                }
                                Button(overviewExpanded ? "Less" : "More…") { overviewExpanded.toggle() }
                                    .font(.footnote).buttonStyle(.borderless)
                                    // A full-size tap target without making the small link look any bigger.
                                    .frame(minWidth: 44, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                                    .accessibilityLabel(overviewExpanded ? "Show less overview" : "Show full overview")
                            }.readingSection("Overview")
                        }.listRowSeparator(.hidden).listSectionSeparator(.hidden)
                    }
                    if let criteria = details["criteria"].array, !criteria.isEmpty {
                        Section { GradingView(criteria: criteria).readingSection("Assessment") }
                            .listRowSeparator(.hidden).listSectionSeparator(.hidden)
                    }
                    if let feedback = details["engagement"]["feedbackComment"].string ?? details["feedback"].string, !feedback.isEmpty {
                        Section { FeedbackView(html: feedback).readingSection("Feedback") }
                            .listRowSeparator(.hidden).listSectionSeparator(.hidden)
                    }
                    Section {
                        ReadingSectionHeader(title: "Photos & Documents").listRowSeparator(.hidden).id("assessment-files")
                        if loadingAttachments { ProgressView("Finding photos & documents…") }
                        if let attachmentError { Text(attachmentError).font(.caption).foregroundStyle(.secondary) }
                        ForEach(attachments) { attachment in
                            AttachmentCard(attachment: attachment, showsRule: attachment.id != attachments.last?.id) { value in rotatedMedia[attachment.id] = value }
                                .listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
                        }
                        if !loadingAttachments && attachments.isEmpty && attachmentError == nil {
                            Text("No files have been released for this assessment.").foregroundStyle(.secondary)
                        }
                    }.listRowSeparator(.hidden).listSectionSeparator(.hidden)
                }
            }.listStyle(.plain).listSectionSpacing(8).listRowSeparator(.hidden).listSectionSeparator(.hidden)
                .contentMargins(.top, 8, for: .scrollContent).overlay { if loading { ProgressView("Reading assessment…").padding(20).background(.regularMaterial) } }
                .refreshable { await model.client?.clearCache(); await load() }
                .task { await lookUpDue() }
                .task { await model.loadTeachersIfNeeded(for: child) }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await shareAssessment() } } label: {
                            if preparingPrint { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
                        }.accessibilityLabel("Share assessment").disabled(details == nil || preparingPrint)
                    }
                }
        }
                .navigationTitle("Assessment").navigationBarTitleDisplayMode(.inline).task { await load() }
    }
    /// The header's date, worded for print: "Due …" when the due date is known, else when the result was released.
    private var printedDate: String? {
        if let due = [assessment.due, listedDue ?? ""].first(where: { !$0.isEmpty }) { return "Due " + reportDate(due) }
        if let releasedAt, !releasedAt.isEmpty { return "Released " + reportDate(releasedAt) }
        return nil
    }
    private func shareAssessment() async {
        guard let details else { return }
        preparingPrint = true; defer { preparingPrint = false }
        do {
            var media: [(AssessmentAttachment, Data)] = []
            for attachment in attachments {
                if let rotated = rotatedMedia[attachment.id] { media.append((attachment, rotated)) }
                else if model.isDemo { media.append((attachment, Demo.mediaData(attachment))) }
                else if let client = model.client { media.append((attachment, try await client.attachmentData(attachment))) }
            }
            let item = PrintableAssessment(assessment: assessment, details: details, media: media, date: printedDate,
                                           teacher: model.teacher(forClass: assessment.metaclass, child: child)?.name, student: child.name)
            try AssessmentPrinting.present([item], jobName: assessment.displayTitle)
        } catch { self.error = error.localizedDescription }
    }
    /// `assessment/get` carries no dates, so an assessment opened from an update finds its due date in the (cached) lists.
    private func lookUpDue() async {
        guard assessment.due.isEmpty, listedDue == nil, !model.isDemo, let client = model.client else { return }
        if let match = try? await client.upcomingAssessments(for: child).first(where: { $0.id == assessment.id }), !match.due.isEmpty {
            listedDue = match.due; return
        }
        if let match = try? await client.allPastAssessments(for: child).first(where: { $0.id == assessment.id }), !match.due.isEmpty {
            listedDue = match.due
        }
    }
    private func load() async {
        loading = true; error = nil; attachmentError = nil
        defer { loading = false }
        do {
            let value: JSONValue
            if model.isDemo { value = Demo.assessmentDetails() }
            else if let client = model.client { value = try await client.assessmentDetails(assessment, for: child) }
            else { return }
            try Task.checkCancellation(); details = value; loading = false
            if model.isDemo { attachments = try Demo.attachments() }
            if !model.isDemo, let client = model.client {
                loadingAttachments = true; defer { loadingAttachments = false }
                do {
                    let files = try await client.assessmentAttachments(assessment, for: child, details: value)
                    try Task.checkCancellation(); attachments = files
                } catch { if !Task.isCancelled { attachmentError = error.localizedDescription } }
            }
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

enum AssessmentPane: Hashable { case results, upcoming, reports }

struct AssessmentPanePicker: View {
    @EnvironmentObject private var model: AppModel
    @Binding var pane: AssessmentPane
    var body: some View {
        Picker("Assessments", selection: $pane) {
            Text("Results").tag(AssessmentPane.results); Text("Upcoming").tag(AssessmentPane.upcoming); Text(model.unreadReportCount > 0 ? "Reports (\(model.unreadReportCount))" : "Reports")
                .accessibilityIdentifier("reports-pane").tag(AssessmentPane.reports)
        }.pickerStyle(.segmented)
    }
}

struct ReportsView: View {
    @EnvironmentObject private var model: AppModel
    /// Set when shown as the Reports segment of Assessments, which puts the segment picker at the top.
    var pane: Binding<AssessmentPane>? = nil
    @State private var reports: [AcademicReport] = []
    @State private var loadedFor: String?
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            if let pane, model.child != nil {
                Section { AssessmentPanePicker(pane: pane).padding(.vertical, 3) }
            }
            if model.child != nil {
                if loading { ProgressView("Reading reports…") }
                if let error { ErrorRow(message: error, retry: { await load() }) }
                if reports.isEmpty && !loading && error == nil {
                    ContentUnavailableView("No reports yet", systemImage: "doc.text", description: Text("Reports appear here when your school releases them."))
                }
                ForEach(reports) { report in
                    NavigationLink { ReportDetailView(report: report, readScope: model.reportsScope) } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "doc.richtext").font(.title).foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(report.title).font(.headline)
                                    if model.isReportUnread(report.id) {
                                        Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(.teal).accessibilityLabel("Unread")
                                    }
                                }
                                Text([report.year, report.term].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline)
                                Text(reportDate(report.date)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 10)
                    }
                }
            } else { ChildPlaceholder() }
        }.listStyle(.plain).navigationTitle(pane == nil ? "Reports" : "Assessments")
            // Returning from a report re-runs this task; only reload for a different child, keeping the position.
            .task(id: model.childID) { if loadedFor != model.childID { await load() } }
            .refreshable { await model.client?.clearCache(); await load(refreshing: true) }
    }
    private func load(refreshing: Bool = false) async {
        guard let child = model.child else { return }
        let scope = model.reportsScope
        loading = true; error = nil; if !refreshing { reports = [] }; defer { loading = false }
        do {
            let values: [AcademicReport]
            if model.isDemo { values = try Demo.reports() }
            else if let client = model.client { values = try await client.reports(for: child) }
            else { return }
            try Task.checkCancellation()
            guard scope == model.reportsScope else { return }
            reports = values; loadedFor = child.id; model.recordReports(values)
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct ReportDetailView: View {
    @EnvironmentObject private var model: AppModel
    let report: AcademicReport
    let readScope: String
    @State private var data: Data?
    @State private var error: String?
    var body: some View {
        Group {
            if let data { PDFReader(data: data) }
            else if let error { ContentUnavailableView { Label("Couldn’t open report", systemImage: "doc.badge.ellipsis") } description: { Text(error) } actions: { Button("Try again") { Task { await load() } } } }
            else { ProgressView("Opening report…") }
        }.navigationTitle(report.title).navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar).task { await load() }
    }
    private func load() async {
        error = nil
        do {
            let value: Data
            if model.isDemo { value = Demo.pdf(child: model.child?.name ?? "Alex Morgan") }
            else if let client = model.client { value = try await client.reportPDF(report) }
            else { return }
            try Task.checkCancellation()
            guard PDFDocument(data: value) != nil else { throw SEQTAError.invalidDocument }; data = value
            model.markReportRead(report.id, scope: readScope)
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct PDFReader: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = false
        view.pageBreakMargins = .zero
        view.backgroundColor = .systemBackground
        view.document = PDFDocument(data: data)
        view.autoScales = true
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) { }
}

struct ErrorRow: View {
    let message: String
    let retry: () async -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
            Button("Try again") { Task { await retry() } }
        }.padding(.vertical, 8)
    }
}
struct ChildPlaceholder: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ContentUnavailableView("Choose a child", systemImage: "person.2", description: Text(model.isLoading ? "Loading the children on this account…" : "No children are available. Check your school account or reconnect using the account menu."))
    }
}

/// Displays school-provided markup as text. Never executes script, loads remote images, or shares session cookies with a WebView.
struct ReadableHTML: View {
    let html: String
    var font: Font = .body
    private var plainText: String { Self.plainText(from: html) }
    static func plainText(from html: String) -> String {
        var text = html
        for pattern in ["(?is)<script\\b[^>]*>.*?</script>", "(?is)<style\\b[^>]*>.*?</style>"] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        // Paragraphs and headings end with a blank line, as on the web; line breaks and list items with a single one.
        text = text.replacingOccurrences(of: "(?i)</(?:p|h[1-6])\\s*>", with: "\n\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<(?:br\\s*/?|/div|/li)\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, value) in [("&nbsp;", " "), ("&#160;", " "), ("&#xA0;", " "), ("&zwsp;", ""), ("\u{200B}", ""), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] { text = text.replacingOccurrences(of: entity, with: value) }
        text = text.replacingOccurrences(of: "[ \t]*\n[ \t]*", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Selectable text is interactive, so it needs a full-size hit area; short summaries in compact rows turn it off.
    var selectable = true
    var body: some View {
        let text = Text(plainText).font(font).lineSpacing(5)
        Group { if selectable { text.textSelection(.enabled) } else { text } }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The app's date format, "10 November 2026" (Lunch has its own, shorter one).
func longDate(_ date: Date) -> String {
    date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "en_AU")))
}

func reportDate(_ value: String) -> String {
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = TimeZone(secondsFromGMT: 0)
    parser.dateFormat = "yyyy-MM-dd"
    guard let date = parser.date(from: String(value.prefix(10))) else { return value }
    parser.locale = Locale(identifier: "en_AU"); parser.dateFormat = "d MMMM yyyy"
    return parser.string(from: date)
}

/// The right-hand slot of an assessment row: the mark when there is one. Without a mark, the same slot says why:
/// a red "Overdue" pill, and/or an outline speech bubble when written feedback has been released. Once there's a mark,
/// both would be redundant, so they're not shown.
struct AssessmentMark: View {
    /// Settings → "Hide marks in lists": marks appear only on the assessment itself; lists show the speech bubble.
    static let hideKey = "hideMarks"
    let assessment: Assessment
    @AppStorage(AssessmentMark.hideKey) private var hideMarks = false
    var body: some View {
        HStack(spacing: 8) {
            if hideMarks && hasMark {
                Image(systemName: "text.bubble").font(.subheadline).foregroundStyle(.primary)
                    .accessibilityLabel("Result released")
            } else {
                if !assessment.grade.isEmpty { Text(assessment.grade).font(.subheadline.bold()) }
                // A bare score means little without its total, so prefer the percentage when SEQTA gives one.
                if let percentage = assessment.displayPercentage { Text(percentage).font(.subheadline.bold()).monospacedDigit() }
                else if !assessment.score.isEmpty { Text(assessment.displayScore).font(.subheadline.bold()) }
            }
            if !hasMark {
                if assessment.overdue {
                    Text("Overdue").font(.caption.weight(.semibold)).foregroundStyle(.white)
                        // A deeper red than .red so small white text clears the 4.5:1 contrast ratio.
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Color(red: 0.75, green: 0.11, blue: 0.11), in: Capsule())
                }
                if assessment.hasFeedback {
                    Image(systemName: "text.bubble").font(.subheadline).foregroundStyle(.primary)
                        .accessibilityLabel("Feedback available")
                }
            }
        }
    }
    private var hasMark: Bool { assessment.hasMark }
}
