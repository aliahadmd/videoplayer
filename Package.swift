// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-or-later
//
// LiPlayer — Native macOS video player built with Swift, AppKit, SwiftUI, and libmpv.
// Copyright (C) 2026 Ali Ahad <https://aliahad.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import PackageDescription
import Foundation

let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "LiPlayer",
    platforms: [.macOS("27.2")],
    products: [.executable(name: "LiPlayer", targets: ["NativePlayer"])],
    targets: [
        .systemLibrary(name: "CMPV", path: "Sources/CMPV"),
        .target(name: "PlayerCore"),
        .executableTarget(
            name: "NativePlayer", dependencies: ["PlayerCore", "CMPV"],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [.unsafeFlags(["-L", projectRoot + "/Vendor/lib", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks", "-Xlinker", "-rpath", "-Xlinker", projectRoot + "/Vendor/lib"])]
        ),
        .testTarget(name: "PlayerCoreTests", dependencies: ["PlayerCore"])
    ]
)
