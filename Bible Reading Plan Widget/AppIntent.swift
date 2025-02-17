//
//  AppIntent.swift
//  Bible Reading Plan Widget
//
//  Created by Matt Greathouse on 2/17/25.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }
}
