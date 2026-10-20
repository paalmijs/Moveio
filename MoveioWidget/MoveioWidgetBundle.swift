//
//  MoveioWidgetBundle.swift
//  MoveioWidget
//
//  Created by Palmijs on 10/21/26.
//

import WidgetKit
import SwiftUI

@main
struct MoveioWidgetBundle: WidgetBundle {
    var body: some Widget {
        MoveioWidget()
        MoveioWidgetControl()
        MoveioWidgetLiveActivity()
    }
}
