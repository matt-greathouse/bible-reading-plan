import SwiftUI
import WidgetKit

struct ReadingPlanWidgetContent: View {
    let plan: ReadingPlan
    let day: Day
    let dayIndex: Int
    let family: WidgetFamily

    private var dayLabel: String {
        "Day \(dayIndex + 1) of \(max(plan.days.count, 1))"
    }

    private var progress: Double {
        guard !plan.days.isEmpty else { return 0 }
        return Double(dayIndex + 1) / Double(plan.days.count)
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 18) {
                    readingDetails
                    Spacer(minLength: 0)
                    progressDetails
                        .frame(width: 92)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    readingDetails
                    Spacer(minLength: 0)
                    progressDetails
                }
            }
        }
        .foregroundStyle(ReadingPlanTheme.primaryText)
        .widgetAccentable()
    }

    private var readingDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("TODAY’S READING")
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(ReadingPlanTheme.secondaryText)
            Text(plan.name)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
            Text(day.toString())
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(ReadingPlanTheme.secondaryText)
        }
    }

    private var progressDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ReadingPlanTheme.accent)
            ProgressView(value: progress)
                .tint(ReadingPlanTheme.accent)
            Text("\(Int(progress * 100))% complete")
                .font(.caption2)
                .foregroundStyle(ReadingPlanTheme.secondaryText)
        }
    }
}

struct EmptyReadingPlanWidget: View {
    var message: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "book.closed")
                .font(.title3)
                .foregroundStyle(ReadingPlanTheme.accent)
            Text(message == nil ? "No Reading Plan Selected" : "Reading Unavailable")
                .font(.headline)
                .foregroundStyle(ReadingPlanTheme.primaryText)
            Text(message ?? "Choose a plan in the app to see today’s reading.")
                .font(.caption)
                .foregroundStyle(ReadingPlanTheme.secondaryText)
        }
    }
}

#if DEBUG
/// Exercises the same widget views in screenshot tests without changing WidgetKit's live data.
struct WidgetPreviewGallery: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Widget Previews").font(.title)
            ReadingPlanWidgetContent(plan: ReadingPlan.previewPlans[0], day: ReadingPlan.previewPlans[0].days[1], dayIndex: 1, family: .systemSmall)
                .padding(16)
                .frame(width: 169, height: 169)
                .background(ReadingPlanTheme.background, in: RoundedRectangle(cornerRadius: 20))
            ReadingPlanWidgetContent(plan: ReadingPlan.previewPlans[1], day: ReadingPlan.previewPlans[1].days[2], dayIndex: 2, family: .systemMedium)
                .padding(16)
                .frame(width: 329, height: 155)
                .background(ReadingPlanTheme.background, in: RoundedRectangle(cornerRadius: 20))
            EmptyReadingPlanWidget()
                .padding(16)
                .frame(width: 169, height: 169)
                .background(ReadingPlanTheme.background, in: RoundedRectangle(cornerRadius: 20))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ReadingPlanTheme.card)
    }
}
#endif
