//
//  Tips.swift
//  Containers
//
//  Created by Axel Martinez on 26/07/2026.
//

import TipKit

struct AddFirstImageTip: Tip {
    @Parameter static var shouldShow: Bool = false

    var title: Text { Text("Start with an image") }
    var message: Text? {
        Text(
            "Add your first image to get started. Images are the foundation for running containers."
        )
    }

    var rules: [Rule] {
        #Rule(Self.$shouldShow) { $0 == true }
    }
}

struct RunContainerTip: Tip {
    var title: Text { Text("Run a container") }
    var message: Text? { Text("Create and run a new container from this image.") }
}
