//
//  AnemOuestWidgetBundle.swift
//  AnemOuestWidget
//
//  Created by Paul Cochard on 05/01/2026.
//

import WidgetKit
import SwiftUI

@main
struct AnemOuestWidgetBundle: WidgetBundle {
    var body: some Widget {
        AnemOuestWidget()
        WaveWidget()
        AnemOuestWidgetControl()
        AnemOuestWidgetLiveActivity()
    }
}
