import SwiftUI
import SEQTAKit

struct AccountsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var notifier = UpdateNotifier.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showSignIn = false
    @State private var removing: SavedAccount?
    var body: some View {
        NavigationStack {
            List {
                Section("Saved school accounts") {
                    ForEach(model.accounts) { account in
                        Button {
                            model.selectAccount(account.id); dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(account.name).foregroundStyle(.primary)
                                    Text(account.school.url.host ?? "").font(.caption).foregroundStyle(.secondary)
                                    Text(account.username).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.accountID == account.id { Image(systemName: "checkmark").foregroundStyle(.teal) }
                            }
                        }.swipeActions { Button("Remove", role: .destructive) { removing = account } }
                    }
                    Button { showSignIn = true } label: { Label("Add or reconnect an account", systemImage: "plus.circle") }
                }
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
                if !model.accounts.isEmpty {
                    Section {
                        Toggle("Notify me about assessments", isOn: $notifier.isEnabled)
                        #if DEBUG
                        Button("Test: announce the newest assessment update") { Task { await notifier.debugAnnounceNewest() } }
                        #endif
                        if notifier.isEnabled && notifier.authorization == .denied {
                            Button("Allow notifications in Settings") {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                            }
                        }
                    } footer: { Text("Alerts for new assessment results and feedback. iOS checks your school’s updates in the background from time to time while your device is unlocked; anything already shown in the app isn’t announced.") }
                }
                Section {
                    if model.isDemo { Button("Leave demo") { model.endDemo(); dismiss() } }
                    else { Button("Explore demo") { model.startDemo(); dismiss() } }
                } footer: { Text("Sessions are stored in this device’s Keychain. Removing an account deletes its saved session from this app. Swipe an account to remove it.") }
                Section { Text("Independent and read-only. No messaging, submissions or edits.").foregroundStyle(.secondary) }
            }.listStyle(.plain).navigationTitle("Accounts")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .sheet(isPresented: $showSignIn, onDismiss: { if model.accountID != nil { dismiss() } }) { SignInView() }
                .confirmationDialog("Remove this saved account?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                    Button("Remove account", role: .destructive) { if let account = removing { Task { await model.remove(account) } }; removing = nil }
                } message: { Text("You can sign in again later. This does not revoke sessions on other devices.") }
        }
    }
}

struct SignInView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var school: String
    /// Opens with `school` filled in when signing in again after a session expires; otherwise empty, with the placeholder.
    init(school: String? = nil) { _school = State(initialValue: school ?? "") }
    @State private var username = ""
    @State private var password = ""
    @State private var setupLink = ""
    @State private var method = "browser"
    @State private var showSchoolSignIn = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Sign-in method", selection: $method) {
                        Text("School sign-in").tag("browser"); Text("Password").tag("password"); Text("Setup link").tag("link")
                    }.pickerStyle(.segmented)
                }
                if method == "link" {
                    Section {
                        SecureField("Paste seqtaengage://sso/…", text: $setupLink).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } header: { Text("Connect mobile app link") } footer: { Text("In your school’s SEQTA Engage website, open Settings → Connect mobile app and copy the link. Your link is a credential; keep it private.") }
                    if let parsed = try? SetupLink(setupLink) {
                        Section("Sign in to this school") { Text(parsed.school.url.absoluteString) }
                    }
                } else {
                    Section {
                        TextField("https://engage.yourschool.edu.au", text: $school).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } header: { Text("School portal") } footer: { Text("Use the SEQTA Engage address provided by your school.") }
                    if method == "password" {
                    Section("Your account") {
                        TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $password).textContentType(.password)
                    }
                    }
                }
                if method == "browser" {
                    Section {
                        Button("Continue to school sign-in") { showSchoolSignIn = true }
                            .disabled((try? School(school)) == nil)
                    } footer: { Text("Use this if your school signs you in through its own login page. A fresh private browser opens for each account. The reader opens automatically once your school confirms sign-in.") }
                } else {
                Section {
                    Button {
                        busy = true; error = nil
                        Task {
                            do {
                                try await model.addAccount(school: school, username: username, password: password, setupLink: method == "link" ? setupLink : "")
                                password = ""; setupLink = ""; dismiss()
                            } catch { self.error = error.localizedDescription }
                            busy = false
                        }
                    } label: { HStack { Text("Sign in"); Spacer(); if busy { ProgressView() } } }
                        .disabled(busy || (method == "link" ? (try? SetupLink(setupLink)) == nil : (try? School(school)) == nil || username.isEmpty || password.isEmpty))
                    if let error { Text(error).foregroundStyle(.red).font(.callout) }
                } footer: { Text("Credentials go directly to the school shown above. Passwords and setup links are not saved; the app stores only your session in Keychain.") }
                }
            }.listStyle(.plain).disabled(busy).navigationTitle("Connect school").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showSchoolSignIn) {
                    if let target = try? School(school) {
                        SchoolSignInView(school: target) { dismiss() }
                    }
                }
                .interactiveDismissDisabled(busy)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
        }
    }
}
