# Schoolkid Engage privacy

Schoolkid Engage connects directly to the school portal you choose. It has no developer-operated server, advertising, analytics, or cloud AI service. School and identity-provider services receive the requests needed for authentication and reading school content.

Passwords and mobile setup tokens are used during authentication and are not saved. Saved account metadata and session cookies are kept in the device Keychain, accessible only while the device is unlocked and restricted to that device. Removing an account deletes its saved local session; it does not revoke sessions on other devices.

The app displays personal information supplied by the school, including names, assessments, reports, timetable and attachments. Reading caches are held in memory for five minutes. Public school names are saved as local preferences. To announce new assessment updates (other bell-feed events are not announced), the app saves the IDs of bell-feed events it has already seen (not their content) as local preferences, and iOS background app refresh reads each saved account's feed directly from the school; notifications are created on the device, with no push server. For the unread badges it also saves the IDs of updates the Updates screen has shown, and a count of those not yet seen. Home Screen and Lock Screen widgets read a snapshot of the selected child's lessons and cycle days for about the next two weeks, kept in a container shared only between the app and its widgets on this device; it is cleared when the account is removed. Office previews and explicit attachment sharing use temporary local files; the app removes those files when the preview or share operation finishes. Files the user exports to another app are controlled by that destination.

Subject classification uses local rules and, when available, Apple's on-device model. It does not send school content to an external AI provider.

Debug simulator builds additionally save an owner-only local authentication file to preserve sign-in across unsigned development rebuilds. That fallback and response-shape diagnostics are excluded from release builds. No real student records or session credentials are included as app resources or test fixtures.

This document describes the app implementation; school and identity-provider privacy policies apply to their services.

Questions about privacy: see [support](https://github.com/geoffwatts/schoolkid-engage/blob/main/SUPPORT.md). Issues are public, so please don't include personal or school details.
