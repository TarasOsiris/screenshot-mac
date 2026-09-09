import Foundation

extension ASCUploadFlowModel {
    // MARK: - Creating a missing App Store localization

    /// Identifies one row's create action. The same project locale appears in every expanded
    /// row-plan card of a destination, so all those buttons must share one in-flight state.
    static func localeCreationKey(versionId: String, projectLocaleCode: String) -> String {
        "\(versionId)|\(projectLocaleCode)"
    }

    /// The App Store locale codes a version already has, lowercased. A project locale can map to
    /// a code some *other* project locale already claimed — a project carrying both `en` and
    /// `en-US` leaves `en` unmatched, because `ASCLocaleMatcher` gives `en-US` to the longer code
    /// — and creating it again is a duplicate App Store Connect will only reject.
    func existingStoreLocaleCodes(versionId: String) -> Set<String> {
        Set((localizationsByVersionId[versionId] ?? []).map { $0.attributes.locale.lowercased() })
    }

    /// Create the App Store localization a project locale has no match for, on one version, then
    /// rebuild the plans so the row picks it up as a candidate. Nothing to do when the App Store
    /// has no such language, or when the version already carries it — the view doesn't offer the
    /// action in either case, and this guard keeps that true if it ever does.
    func createAppStoreLocalization(projectLocaleCode: String, versionId: String) async {
        guard let storeCode = ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: projectLocaleCode),
              !existingStoreLocaleCodes(versionId: versionId).contains(storeCode.lowercased())
        else { return }
        let key = Self.localeCreationKey(versionId: versionId, projectLocaleCode: projectLocaleCode)
        guard !creatingLocaleKeys.contains(key) else { return }

        creatingLocaleKeys.insert(key)
        localeCreationErrors[key] = nil
        defer { creatingLocaleKeys.remove(key) }

        CrashReportingService.breadcrumb(.upload, "asc create version localization", data: ["locale": storeCode])
        do {
            let created = try await AppStoreConnectVersionMetadata.createLocalization(
                api,
                versionId: versionId,
                locale: storeCode,
                fallbackAttributes: fallbackCopy(versionId: versionId)
            )
            // Replace rather than append: a Refresh can land mid-create (it deliberately doesn't
            // block this action), and two candidates sharing one id would break `ForEach`.
            var localizations = localizationsByVersionId[versionId] ?? []
            localizations.removeAll { $0.id == created.id || $0.attributes.locale == created.attributes.locale }
            localizations.append(created)
            localizationsByVersionId[versionId] = localizations
            updateDestinationPlans(buildDestinationPlans(preserving: destinationPlans))
        } catch {
            // Inline on the row rather than `errorMessage`: one locale App Store Connect won't
            // take shouldn't blank out the whole plan screen.
            localeCreationErrors[key] = error.localizedDescription
            CrashReportingService.breadcrumb(
                .upload,
                "asc create version localization failed",
                data: ["locale": storeCode],
                level: .warning
            )
        }
    }

    /// The attributes `createLocalization` may retry with, taken from the version's own base
    /// locale so copied text is at least the user's own. Release notes are the exception: the
    /// base language's notes on a foreign storefront read worse than the neutral default.
    private func fallbackCopy(versionId: String) -> [String: AnyEncodable] {
        let localizations = localizationsByVersionId[versionId] ?? []
        let codes = localizations.map(\.attributes.locale).sorted()
        guard let baseCode = baseLocaleCode(among: codes),
              let base = localizations.first(where: { $0.attributes.locale == baseCode })
        else { return ["whatsNew": AnyEncodable(Self.defaultWhatsNew)] }

        var attributes: [String: AnyEncodable] = ["whatsNew": AnyEncodable(Self.defaultWhatsNew)]
        if let description = base.attributes.description, !description.isEmpty {
            attributes["description"] = AnyEncodable(description)
        }
        if let keywords = base.attributes.keywords, !keywords.isEmpty {
            attributes["keywords"] = AnyEncodable(keywords)
        }
        return attributes
    }
}
