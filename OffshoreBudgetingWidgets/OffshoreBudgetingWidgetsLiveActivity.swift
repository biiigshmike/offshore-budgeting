//
//  OffshoreBudgetingWidgetsLiveActivity.swift
//  OffshoreBudgetingWidgets
//
//  Created by Michael Brown on 1/27/26.
//

//import ActivityKit
//import WidgetKit
//import SwiftUI
//
//struct OffshoreBudgetingWidgetsAttributes: ActivityAttributes {
//    public struct ContentState: Codable, Hashable {
//        // Dynamic stateful properties about your activity go here!
//        var emoji: String
//    }
//
//    // Fixed non-changing properties about your activity go here!
//    var name: String
//}
//
//struct OffshoreBudgetingWidgetsLiveActivity: Widget {
//    var body: some WidgetConfiguration {
//        ActivityConfiguration(for: OffshoreBudgetingWidgetsAttributes.self) { context in
//            // Lock screen/banner UI goes here
//            VStack {
//                Text("Hello \(context.state.emoji)")
//            }
//            .activityBackgroundTint(Color.cyan)
//            .activitySystemActionForegroundColor(Color.black)
//
//        } dynamicIsland: { context in
//            DynamicIsland {
//                // Expanded UI goes here.  Compose the expanded UI through
//                // various regions, like leading/trailing/center/bottom
//                DynamicIslandExpandedRegion(.leading) {
//                    Text("Leading")
//                }
//                DynamicIslandExpandedRegion(.trailing) {
//                    Text("Trailing")
//                }
//                DynamicIslandExpandedRegion(.bottom) {
//                    Text("Bottom \(context.state.emoji)")
//                    // more content
//                }
//            } compactLeading: {
//                Text("L")
//            } compactTrailing: {
//                Text("T \(context.state.emoji)")
//            } minimal: {
//                Text(context.state.emoji)
//            }
//            .widgetURL(URL(string: "http://www.apple.com"))
//            .keylineTint(Color.red)
//        }
//    }
//}
//
//extension OffshoreBudgetingWidgetsAttributes {
//    fileprivate static var preview: OffshoreBudgetingWidgetsAttributes {
//        OffshoreBudgetingWidgetsAttributes(name: "World")
//    }
//}
//
//extension OffshoreBudgetingWidgetsAttributes.ContentState {
//    fileprivate static var smiley: OffshoreBudgetingWidgetsAttributes.ContentState {
//        OffshoreBudgetingWidgetsAttributes.ContentState(emoji: "😀")
//     }
//     
//     fileprivate static var starEyes: OffshoreBudgetingWidgetsAttributes.ContentState {
//         OffshoreBudgetingWidgetsAttributes.ContentState(emoji: "🤩")
//     }
//}
//
//#Preview("Notification", as: .content, using: OffshoreBudgetingWidgetsAttributes.preview) {
//   OffshoreBudgetingWidgetsLiveActivity()
//} contentStates: {
//    OffshoreBudgetingWidgetsAttributes.ContentState.smiley
//    OffshoreBudgetingWidgetsAttributes.ContentState.starEyes
//}
