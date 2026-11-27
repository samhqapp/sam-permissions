// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "sam-permissions",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SamPermissions", targets: ["SamPermissions"])],
    dependencies: [.package(url: "https://github.com/jaywcjlove/PermissionFlow.git", exact: "2.11.4")],
    targets: [
        .target(name: "SamPermissions", dependencies: [
            .product(name: "PermissionFlow", package: "PermissionFlow"),
            .product(name: "PermissionFlowExtendedStatus", package: "PermissionFlow"),
            .product(name: "PermissionFlowCameraStatus", package: "PermissionFlow"),
        ]),
        .testTarget(name: "SamPermissionsTests", dependencies: [
            "SamPermissions", .product(name: "PermissionFlow", package: "PermissionFlow"),
        ]),
    ]
)
