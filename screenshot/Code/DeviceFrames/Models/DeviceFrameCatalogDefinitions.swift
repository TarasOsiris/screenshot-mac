import SwiftUI

enum DeviceFrameCatalogDefinitions {
    private static let iphone17Spec = DeviceFrameImageSpec(
        frameWidth: 1350,
        frameHeight: 2760,
        screenLeft: 72,
        screenTop: 69,
        screenRight: 72,
        screenBottom: 69,
        screenCornerRadius: 165
    )
    private static let iphone17ProMaxSpec = DeviceFrameImageSpec(
        frameWidth: 1470,
        frameHeight: 3000,
        screenLeft: 75,
        screenTop: 66,
        screenRight: 75,
        screenBottom: 66,
        screenCornerRadius: 170
    )
    private static let iphoneAirSpec = DeviceFrameImageSpec(
        frameWidth: 1380,
        frameHeight: 2880,
        screenLeft: 60,
        screenTop: 72,
        screenRight: 60,
        screenBottom: 72,
        screenCornerRadius: 165
    )
    private static let macbookAir13Spec = DeviceFrameImageSpec(
        frameWidth: 3220,
        frameHeight: 2100,
        screenLeft: 330,
        screenTop: 218,
        screenRight: 330,
        screenBottom: 218,
        screenCornerRadius: 34
    )
    private static let macbookPro14Spec = DeviceFrameImageSpec(
        frameWidth: 3944,
        frameHeight: 2564,
        screenLeft: 460,
        screenTop: 300,
        screenRight: 460,
        screenBottom: 300,
        screenCornerRadius: 40
    )
    private static let macbookPro16Spec = DeviceFrameImageSpec(
        frameWidth: 4340,
        frameHeight: 2860,
        screenLeft: 442,
        screenTop: 313,
        screenRight: 442,
        screenBottom: 313,
        screenCornerRadius: 38
    )
    private static let imac24Spec = DeviceFrameImageSpec(
        frameWidth: 4760,
        frameHeight: 4040,
        screenLeft: 140,
        screenTop: 160,
        screenRight: 140,
        screenBottom: 1360,
        screenCornerRadius: 0
    )
    private static let ipadPro11Spec = DeviceFrameImageSpec(
        frameWidth: 1880,
        frameHeight: 2640,
        screenLeft: 106,
        screenTop: 110,
        screenRight: 106,
        screenBottom: 110,
        screenCornerRadius: 55
    )
    private static let ipadPro13Spec = DeviceFrameImageSpec(
        frameWidth: 2300,
        frameHeight: 3000,
        screenLeft: 118,
        screenTop: 124,
        screenRight: 118,
        screenBottom: 124,
        screenCornerRadius: 54
    )
    private static let iphone16ModelSpec = DeviceFrameImageSpec(
        frameWidth: 148.05,
        frameHeight: 300.0,
        screenLeft: 7.6025,
        screenTop: 6.653,
        screenRight: 7.6025,
        screenBottom: 6.653,
        screenCornerRadius: 18
    )
    private static let iphone16USDZModel = DeviceFrameModelSpec(
        resourceName: "Iphone_17_pro",
        resourceExtension: "usdz",
        resourceSubdirectory: "DeviceModels",
        screenMaterialName: "Screen_BG",
        disabledNodeNames: [],
        screenRenderingMode: .replaceMaterial,
        targetBodyHeight: 2.05,
        cameraDistance: 5.4,
        baseYawDegrees: 0,
        defaultPitch: -22,
        defaultYaw: -14,
        screenUVPadding: 0.03,
        screenUVOffsetY: -0.02
    )

    static let entries: [DeviceFrameCatalogEntry] = [
        DeviceFrameCatalogEntry(
            groupId: "iphone17",
            modelName: "iPhone 17",
            family: .iphone,
            fallbackCategory: .iphone,
            colors: ["Black", "Lavender", "Mist Blue", "Sage", "White"],
            baseSpec: iphone17Spec,
            modelSpec: nil,
            landscapeOnly: false,
            suggestedSizePreset: "1206x2622"
        ),
        DeviceFrameCatalogEntry(
            groupId: "iphone17pro",
            modelName: "iPhone 17 Pro",
            family: .iphone,
            fallbackCategory: .iphone,
            colors: ["Cosmic Orange", "Deep Blue", "Silver"],
            baseSpec: iphone17Spec,
            modelSpec: nil,
            landscapeOnly: false,
            suggestedSizePreset: "1206x2622"
        ),
        DeviceFrameCatalogEntry(
            groupId: "iphone17promax",
            modelName: "iPhone 17 Pro Max",
            family: .iphone,
            fallbackCategory: .iphone,
            colors: ["Cosmic Orange", "Deep Blue", "Silver"],
            baseSpec: iphone17ProMaxSpec,
            modelSpec: nil,
            landscapeOnly: false,
            suggestedSizePreset: "1320x2868"
        ),
        DeviceFrameCatalogEntry(
            groupId: "iphoneair",
            modelName: "iPhone Air",
            family: .iphone,
            fallbackCategory: .iphone,
            colors: ["Cloud White", "Light Gold", "Sky Blue", "Space Black"],
            baseSpec: iphoneAirSpec,
            modelSpec: nil,
            landscapeOnly: false,
            suggestedSizePreset: "1260x2736"
        ),
        DeviceFrameCatalogEntry(
            groupId: "iphone16model",
            modelName: "iPhone 17 (3D)",
            family: .iphone,
            fallbackCategory: .iphone,
            colors: ["Default"],
            baseSpec: iphone16ModelSpec,
            modelSpec: iphone16USDZModel,
            landscapeOnly: false,
            suggestedSizePreset: nil
        ),
        DeviceFrameCatalogEntry(
            groupId: "ipadpro11",
            modelName: "iPad Pro 11\"",
            family: .ipad,
            fallbackCategory: .ipadPro11,
            colors: ["Silver", "Space Gray"],
            baseSpec: ipadPro11Spec,
            modelSpec: nil,
            landscapeOnly: false,
            suggestedSizePreset: "1668x2420"
        ),
        DeviceFrameCatalogEntry(
            groupId: "ipadpro13",
            modelName: "iPad Pro 13\"",
            family: .ipad,
            fallbackCategory: .ipadPro13,
            colors: ["Silver", "Space Gray"],
            baseSpec: ipadPro13Spec,
            modelSpec: nil,
            landscapeOnly: false,
            suggestedSizePreset: "2064x2752"
        ),
        DeviceFrameCatalogEntry(
            groupId: "macbookair13",
            modelName: "MacBook Air 13\"",
            family: .mac,
            fallbackCategory: .macbook,
            colors: ["Midnight"],
            baseSpec: macbookAir13Spec,
            modelSpec: nil,
            landscapeOnly: true,
            suggestedSizePreset: "2560x1600"
        ),
        DeviceFrameCatalogEntry(
            groupId: "macbookpro14",
            modelName: "MacBook Pro 14\"",
            family: .mac,
            fallbackCategory: .macbook,
            colors: ["Silver"],
            baseSpec: macbookPro14Spec,
            modelSpec: nil,
            landscapeOnly: true,
            suggestedSizePreset: "2880x1800"
        ),
        DeviceFrameCatalogEntry(
            groupId: "macbookpro16",
            modelName: "MacBook Pro 16\"",
            family: .mac,
            fallbackCategory: .macbook,
            colors: ["Silver"],
            baseSpec: macbookPro16Spec,
            modelSpec: nil,
            landscapeOnly: true,
            suggestedSizePreset: "2880x1800"
        ),
        DeviceFrameCatalogEntry(
            groupId: "imac24",
            modelName: "iMac 24\"",
            family: .mac,
            fallbackCategory: .macbook,
            colors: ["Silver"],
            baseSpec: imac24Spec,
            modelSpec: nil,
            landscapeOnly: true,
            suggestedSizePreset: "2880x1800"
        ),
    ]
}