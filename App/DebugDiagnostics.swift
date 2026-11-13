#if DEBUG
import Foundation
import SwiftUI
import WidgetKit
import LMSKit

actor ShapeRecordingTransport: HTTPTransport {
    private let base = URLSessionTransport()
    private var records: [[String: String]] = []
    /// Class IDs seen on lessons and on assessments; only the size of their overlap is reported.
    private var lessonClassIDs: Set<String> = [], assessmentClassIDs: Set<String> = []
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await base.send(request)
        var record = ["route": request.url?.path ?? "", "httpStatus": String(response.statusCode)]
        if let location = response.value(forHTTPHeaderField: "Location"), let url = URL(string: location, relativeTo: request.url) {
            record["redirectHost"] = url.host ?? ""
        }
        if let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
            record["shape"] = Self.shape(json, depth: 0)
            record["status"] = json["status"].string
            for item in json["payload"]["items"].array ?? [] { if let id = item["metaID"].string { lessonClassIDs.insert(id) } }
            for list in [json["payload"].array ?? [], json["payload"]["tasks"].array ?? [], json["payload"]["feedback"].array ?? []] {
                for item in list { if let id = item["metaclassID"].string { assessmentClassIDs.insert(id) } }
            }
            if request.url?.path.hasSuffix("load/timetable") == true {
                if let schedule = try? TimetableSchedule(json: json["payload"]) {
                    record["timetableDecoded"] = "true"; record["lessonCount"] = String(schedule.entries.count)
                } else { record["timetableDecoded"] = "false" }
            }
            if request.url?.path.hasSuffix("assessment/get") == true {
                // Whether `percentage` is 0–100 or 0–1, judged against score ÷ target; no values are kept.
                for criterion in json["payload"]["criteria"].array ?? [] {
                    let results = criterion["results"]
                    if let p = results["percentage"].string.flatMap(Double.init), let score = results["score"].string.flatMap(Double.init),
                       let target = results["target"].string.flatMap(Double.init), target > 0 {
                        let ratio = score / target
                        record["percentageScale"] = abs(p - ratio * 100) < 1 ? "0-100" : abs(p - ratio) < 0.01 ? "0-1" : "other"
                    }
                }
                var selected = 0; var preserved = 0; var markMatches = 0
                for criterion in json["payload"]["criteria"].array ?? [] {
                    for line in criterion["rubric"]["lines"].array ?? [] {
                        guard let lineID = line["id"].string, let selectedID = criterion["rubricScore"][lineID]["id"].string,
                              let original = (line["descriptors"].array ?? []).first(where: { $0["id"].string == selectedID }) else { continue }
                        selected += 1
                        if let rendered = RubricPresentation.orderedDescriptors(in: line, mode: criterion["rubric"]["mode"].string ?? "numeric").first(where: { $0["id"].string == selectedID }), rendered == original { preserved += 1 }
                        let awarded = criterion["rubricScore"][lineID]
                        if awarded["grade"].string == original["grade"].string && awarded["score"].string == original["score"].string { markMatches += 1 }
                    }
                }
                record["rubricSelectedCount"] = String(selected)
                record["rubricIdentityPreserved"] = String(preserved == selected)
                record["rubricAwardedMarksMatch"] = String(markMatches == selected)
            }
            if ["student", "contact", "staff"].contains(json["payload"]["type"].string ?? "") { record["personType"] = json["payload"]["type"].string }
        }
        records.append(record)
        return (data, response)
    }
    private static func shape(_ value: JSONValue, depth: Int) -> String {
        switch value {
        case .object(let object):
            if depth > 7 { return "object(" + object.keys.sorted().joined(separator: ",") + ")" }
            return "{" + object.keys.sorted().map { $0 + ":" + shape(object[$0]!, depth: depth + 1) }.joined(separator: ",") + "}"
        case .array(let values): return "array[\(values.count)]" + (values.first.map { shape($0, depth: depth + 1) } ?? "")
        case .string: return "string"
        case .number: return "number"
        case .bool: return "bool"
        case .null: return "null"
        }
    }
    func summary() -> [[String: String]] {
        records + [["route": "summary", "lessonClassIDs": String(lessonClassIDs.count), "assessmentClassIDs": String(assessmentClassIDs.count),
                    "sharedClassIDs": String(lessonClassIDs.intersection(assessmentClassIDs).count)]]
    }
}

@MainActor
func writeDiagnosticShapes(timetableOnly: Bool = false) async {
    do {
        guard let account = try KeychainAccountStore().load().first else { return }
        let transport = ShapeRecordingTransport()
        let client = SEQTAClient(account: account, transport: transport)
        if timetableOnly {
            if let child = try await client.children().first {
                var calendar = Calendar(identifier: .gregorian); calendar.firstWeekday = 2
                let start = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
                _ = try await client.timetable(for: child, from: start, until: calendar.date(byAdding: .day, value: 6, to: start)!)
            }
        } else { await client.diagnosticReads() }
        let data = try JSONEncoder().encode(await transport.summary())
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try data.write(to: directory.appendingPathComponent("response-shapes.json"), options: .atomic)
    } catch { }
}
/// Renders the real widget views at Home Screen sizes for simulator layout checks, using fictional data only.
struct WidgetLayoutPreview: View {
    @State private var connected = true
    private var snapshot: WidgetSnapshot {
        var snapshot = WidgetSnapshot.sample
        snapshot.lunchBalance = connected ? Decimal(string: "18.50") : nil
        return snapshot
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Toggle("MSA connected", isOn: $connected).accessibilityIdentifier("widget-msa-connected")
                SchoolDayView(entry: SchoolDayEntry(date: .now, snapshot: snapshot), familyOverride: .systemSmall)
                    .padding(16).frame(width: 170, height: 170)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityIdentifier("small-widget-preview")
                SchoolDayView(entry: SchoolDayEntry(date: .now, snapshot: snapshot), familyOverride: .systemMedium)
                    .padding(16).frame(width: 350, height: 170)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityIdentifier("medium-widget-preview")
            }.padding()
        }.navigationTitle("Widget layout")
    }
}
#endif
