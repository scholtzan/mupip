import Foundation
import SwiftUI

enum DefaultSettings {
    static let refreshFrequency = 30.0
    static let inactivityThreshold = 60.0
    static let captureHeight = 200
    static let captureCorner: Corner = .topRight
}

enum Corner: String, Equatable, CaseIterable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
    
    var localizedName: LocalizedStringKey { LocalizedStringKey(rawValue) }
}

struct SettingsView: View {
    @AppStorage("refreshFrequency") private var refreshFrequency = DefaultSettings.refreshFrequency
    @AppStorage("inactivityThreshold") private var inactivityThreshold = DefaultSettings.inactivityThreshold
    @AppStorage("captureHeight") private var captureHeight = DefaultSettings.captureHeight
    @AppStorage("captureCorner") private var captureCorner = DefaultSettings.captureCorner
    
    var body: some View {
        VStack {
            GroupBox("Capture Settings") {
                VStack {
                    Slider(
                        value: $refreshFrequency,
                        in: 1...60,
                        step: 1,
                        onEditingChanged: { editing in
                            return
                        },
                        minimumValueLabel: Text("1Hz"),
                        maximumValueLabel: Text("60Hz"),
                        label: { Text("Refresh Frequency: ") }
                    )
                    Slider(
                        value: $inactivityThreshold,
                        in: 1...300,
                        step: 5,
                        onEditingChanged: { editing in
                            return
                        },
                        minimumValueLabel: Text("1s"),
                        maximumValueLabel: Text("5min"),
                        label: { Text("Inactivity Threshold: ") }
                    )
                    HStack {
                        Text("Default Capture Height (px): ")
                        TextField("", value: $captureHeight, formatter: NumberFormatter())
                    }
                    Picker("Corner to Gather Captures: ", selection: $captureCorner) {
                        ForEach(Corner.allCases, id: \.self) { value in
                            Text(value.localizedName).tag(value)
                        }
                    }
                }
                
//                GroupBox("Permissions") {
//                    "todo"
//                }
                            
            }.padding(15)
        }
    }
}

