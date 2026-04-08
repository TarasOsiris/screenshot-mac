import Foundation

enum DeviceFrameCatalog {
    static let groups: [DeviceFrameGroup] = DeviceFrameCatalogDefinitions.entries.map(makeGroup)

    static let sections: [DeviceFrameCatalogSection] = DeviceFrameFamily.allCases.compactMap { family in
        let groups = groups(for: family)
        let categories = family.genericCategories
        guard !categories.isEmpty || !groups.isEmpty else { return nil }
        return DeviceFrameCatalogSection(family: family, categories: categories, groups: groups)
    }

    static let allFrames: [DeviceFrame] = groups.flatMap(\.frames)

    private static let framesByID: [String: DeviceFrame] = Dictionary(
        uniqueKeysWithValues: allFrames.map { ($0.id, $0) }
    )

    private static let groupIdByFrameId: [String: String] = {
        var map: [String: String] = [:]
        for group in groups {
            for frame in group.frames {
                map[frame.id] = group.id
            }
        }
        return map
    }()

    private static let groupsByID: [String: DeviceFrameGroup] = Dictionary(
        uniqueKeysWithValues: groups.map { ($0.id, $0) }
    )

    private static let firstPortraitFrameByCategory: [DeviceCategory: String] = {
        var map: [DeviceCategory: String] = [:]
        for frame in allFrames where !frame.isLandscape {
            if map[frame.fallbackCategory] == nil {
                map[frame.fallbackCategory] = frame.id
            }
        }
        return map
    }()

    static func frame(for id: String) -> DeviceFrame? {
        framesByID[id]
    }

    static func firstPortraitFrameId(for category: DeviceCategory) -> String? {
        firstPortraitFrameByCategory[category]
    }

    static func group(forFrameId frameId: String) -> DeviceFrameGroup? {
        groupIdByFrameId[frameId].flatMap { groupsByID[$0] }
    }

    static func colorGroup(forFrameId frameId: String) -> DeviceFrameColorGroup? {
        group(forFrameId: frameId)?.colorGroups.first { colorGroup in
            colorGroup.frames.contains { $0.id == frameId }
        }
    }

    static func preferredFrame(forGroupId groupId: String, matching currentFrameId: String? = nil) -> DeviceFrame? {
        guard let group = groupsByID[groupId] else { return nil }
        let currentFrame = currentFrameId.flatMap { frame(for: $0) }
        return preferredFrame(in: group, matching: currentFrame)
    }

    static func variant(
        forFrameId frameId: String,
        colorGroupId: String? = nil,
        isLandscape: Bool? = nil
    ) -> DeviceFrame? {
        guard let frame = frame(for: frameId),
              let group = group(forFrameId: frameId) else { return nil }

        let targetColorGroup = colorGroupId.flatMap { id in
            group.colorGroups.first { $0.id == id }
        } ?? colorGroup(forFrameId: frameId) ?? group.colorGroups.first

        guard let targetColorGroup else { return nil }
        let targetLandscape = isLandscape ?? frame.isLandscape
        return targetColorGroup.frames.first(where: { $0.isLandscape == targetLandscape }) ?? targetColorGroup.frames.first
    }

    static func toggledOrientation(for id: String) -> DeviceFrame? {
        guard let frame = frame(for: id) else { return nil }
        return variant(forFrameId: id, isLandscape: !frame.isLandscape)
    }

    static func suggestedSizePreset(forFrameId frameId: String) -> String? {
        guard let frame = framesByID[frameId],
              let preset = group(forFrameId: frameId)?.suggestedSizePreset else {
            return nil
        }

        if frame.isLandscape,
           let parsed = parseSizeString(preset),
           parsed.width < parsed.height {
            return "\(Int(parsed.height))x\(Int(parsed.width))"
        }

        return preset
    }

    private static func groups(for family: DeviceFrameFamily) -> [DeviceFrameGroup] {
        groups.filter { $0.family == family }
    }

    private static func preferredFrame(in group: DeviceFrameGroup, matching currentFrame: DeviceFrame?) -> DeviceFrame? {
        let preferredColorName = currentFrame?.colorName
        let preferredOrientation = currentFrame?.isLandscape ?? false

        let preferredColorGroup = group.colorGroups.first(where: { $0.name == preferredColorName }) ?? group.colorGroups.first
        return preferredColorGroup?.frames.first(where: { $0.isLandscape == preferredOrientation })
            ?? preferredColorGroup?.frames.first(where: { !$0.isLandscape })
            ?? preferredColorGroup?.frames.first
    }

    private static func makeGroup(from entry: DeviceFrameCatalogEntry) -> DeviceFrameGroup {
        let landscapeSpec = entry.landscapeOnly ? entry.baseSpec : entry.baseSpec.landscape
        let orientations: [Bool] = entry.landscapeOnly ? [true] : [false, true]

        let colorGroups = entry.colors.map { color -> DeviceFrameColorGroup in
            let slug = color.lowercased().replacingOccurrences(of: " ", with: "")
            let frames = orientations.map { isLandscape in
                let orientation = isLandscape ? "landscape" : "portrait"
                let frameId = "\(entry.groupId)-\(slug)-\(orientation)"
                let usesRotation = isLandscape && entry.landscapeFromRotation
                let assetSlug = usesRotation ? "\(entry.groupId)-\(slug)-portrait" : frameId
                return DeviceFrame(
                    id: frameId,
                    modelName: entry.modelName,
                    colorName: color,
                    isLandscape: isLandscape,
                    fallbackCategory: entry.fallbackCategory,
                    imageName: entry.modelSpec == nil ? "DeviceFrames/\(assetSlug)" : nil,
                    spec: isLandscape ? landscapeSpec : entry.baseSpec,
                    modelSpec: entry.modelSpec,
                    iconOverride: entry.iconOverride,
                    isLandscapeRotation: usesRotation
                )
            }

            return DeviceFrameColorGroup(
                id: "\(entry.groupId)-\(slug)",
                name: color,
                frames: frames
            )
        }

        return DeviceFrameGroup(
            id: entry.groupId,
            name: entry.modelName,
            family: entry.family,
            suggestedSizePreset: entry.suggestedSizePreset,
            colorGroups: colorGroups
        )
    }
}