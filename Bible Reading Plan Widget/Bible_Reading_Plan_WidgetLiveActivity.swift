//
//  Bible_Reading_Plan_WidgetLiveActivity.swift
//  Bible Reading Plan Widget
//
//  Created by Matt Greathouse on 2/17/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct Bible_Reading_Plan_WidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct Bible_Reading_Plan_WidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Bible_Reading_Plan_WidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension Bible_Reading_Plan_WidgetAttributes {
    fileprivate static var preview: Bible_Reading_Plan_WidgetAttributes {
        Bible_Reading_Plan_WidgetAttributes(name: "World")
    }
}

extension Bible_Reading_Plan_WidgetAttributes.ContentState {
    fileprivate static var smiley: Bible_Reading_Plan_WidgetAttributes.ContentState {
        Bible_Reading_Plan_WidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: Bible_Reading_Plan_WidgetAttributes.ContentState {
         Bible_Reading_Plan_WidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: Bible_Reading_Plan_WidgetAttributes.preview) {
   Bible_Reading_Plan_WidgetLiveActivity()
} contentStates: {
    Bible_Reading_Plan_WidgetAttributes.ContentState.smiley
    Bible_Reading_Plan_WidgetAttributes.ContentState.starEyes
}
