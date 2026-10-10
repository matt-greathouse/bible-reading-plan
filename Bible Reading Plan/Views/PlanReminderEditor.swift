import SwiftUI

struct PlanReminderEditor: View {
    let store: ReadingPlanStore
    @ObservedObject var reminders: ReadingReminderManager
    let plan: CatalogPlan
    @State private var draft: PlanReminder
    @State private var saving = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(store: ReadingPlanStore, plan: CatalogPlan) {
        self.store = store
        self.reminders = store.reminders
        self.plan = plan
        _draft = State(initialValue: store.reminders.configuration(for: plan.id))
    }

    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(from: DateComponents(hour: draft.hour, minute: draft.minute)) ?? Date()
        }, set: {
            let components = Calendar.current.dateComponents([.hour, .minute], from: $0)
            draft.hour = components.hour ?? 8
            draft.minute = components.minute ?? 0
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Reminder", isOn: $draft.enabled).accessibilityIdentifier("reminder-enabled")
                    if draft.enabled {
                        DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("reminder-time")
                    }
                } header: { Text(plan.plan.name) } footer: {
                    Text("Reminders open this plan in Today’s Readings. Times follow this device’s local time.")
                }
                if draft.enabled {
                    Section("Repeat") {
                        ForEach(0..<7, id: \.self) { offset in
                            let weekday = (Calendar.current.firstWeekday - 1 + offset) % 7 + 1
                            Toggle(Calendar.current.weekdaySymbols[weekday - 1], isOn: Binding(
                                get: { draft.weekdays.contains(weekday) },
                                set: { enabled in
                                    if enabled { draft.weekdays.insert(weekday) }
                                    else { draft.weekdays.remove(weekday) }
                                }))
                            .accessibilityIdentifier("reminder-weekday-\(weekday)")
                        }
                        if draft.weekdays.isEmpty { Text("Choose at least one weekday.").foregroundStyle(.red) }
                    }
                }
                if reminders.blocked {
                    Section {
                        Text("Notifications are turned off in Settings. Your schedule is saved.")
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Open Settings", destination: url)
                        }
                    }
                }
                if let message = error ?? reminders.errors[plan.id] {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .disabled(saving)
            .scrollContentBackground(.hidden)
            .background(ReadingPlanTheme.background)
            .navigationTitle("Reading Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            do {
                                try await reminders.save(draft, for: plan.id)
                                await store.reconcileReminders()
                                if let failure = reminders.errors[plan.id] { error = failure }
                                else { dismiss() }
                            } catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }
                    .disabled(saving || !draft.isValid)
                    .accessibilityIdentifier("save-reminder")
                }
            }
            .tint(ReadingPlanTheme.accent)
            .interactiveDismissDisabled(saving)
        }
    }
}
