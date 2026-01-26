import Foundation

struct LocalProfile: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var storeFilename: String
}

enum LocalProfilesStore {

    static let profilesKey: String = "profiles_local_json"
    static let activeProfileIDKey: String = "profiles_activeLocalID"

    private static let defaultProfileID: String = "default"
    private static let defaultProfileName: String = "On Device"
    private static let defaultStoreFilename: String = "Local.store"

    static func ensureDefaultProfileExists(userDefaults: UserDefaults = .standard) {
        let profiles = loadProfiles(userDefaults: userDefaults)
        if profiles.contains(where: { $0.id == defaultProfileID }) {
            if activeProfileID(userDefaults: userDefaults).isEmpty {
                userDefaults.set(defaultProfileID, forKey: activeProfileIDKey)
            }
            return
        }

        var newProfiles = profiles
        newProfiles.insert(
            LocalProfile(id: defaultProfileID, name: defaultProfileName, storeFilename: defaultStoreFilename),
            at: 0
        )
        saveProfiles(newProfiles, userDefaults: userDefaults)

        if activeProfileID(userDefaults: userDefaults).isEmpty {
            userDefaults.set(defaultProfileID, forKey: activeProfileIDKey)
        }
    }

    static func loadProfiles(userDefaults: UserDefaults = .standard) -> [LocalProfile] {
        guard let data = userDefaults.data(forKey: profilesKey) else { return [] }
        return (try? JSONDecoder().decode([LocalProfile].self, from: data)) ?? []
    }

    static func saveProfiles(_ profiles: [LocalProfile], userDefaults: UserDefaults = .standard) {
        let data = (try? JSONEncoder().encode(profiles)) ?? Data()
        userDefaults.set(data, forKey: profilesKey)
    }

    static func activeProfileID(userDefaults: UserDefaults = .standard) -> String {
        userDefaults.string(forKey: activeProfileIDKey) ?? ""
    }

    static func setActiveProfileID(_ id: String, userDefaults: UserDefaults = .standard) {
        userDefaults.set(id, forKey: activeProfileIDKey)
    }

    static func activeProfile(userDefaults: UserDefaults = .standard) -> LocalProfile {
        ensureDefaultProfileExists(userDefaults: userDefaults)
        let profiles = loadProfiles(userDefaults: userDefaults)
        let id = activeProfileID(userDefaults: userDefaults)
        return profiles.first(where: { $0.id == id })
        ?? profiles.first(where: { $0.id == defaultProfileID })
        ?? LocalProfile(id: defaultProfileID, name: defaultProfileName, storeFilename: defaultStoreFilename)
    }

    static func makeNewProfile(
        name: String,
        userDefaults: UserDefaults = .standard
    ) -> LocalProfile {
        ensureDefaultProfileExists(userDefaults: userDefaults)

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileName = trimmed.isEmpty ? "Profile" : trimmed

        let id = UUID().uuidString
        let filename = "Local-\(id).store"
        let profile = LocalProfile(id: id, name: profileName, storeFilename: filename)

        var profiles = loadProfiles(userDefaults: userDefaults)
        profiles.append(profile)
        saveProfiles(profiles, userDefaults: userDefaults)
        return profile
    }

    static func renameProfile(id: String, newName: String, userDefaults: UserDefaults = .standard) {
        var profiles = loadProfiles(userDefaults: userDefaults)
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        if id == defaultProfileID { return }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        profiles[index].name = trimmed
        saveProfiles(profiles, userDefaults: userDefaults)
    }

    static func deleteProfile(id: String, userDefaults: UserDefaults = .standard) {
        ensureDefaultProfileExists(userDefaults: userDefaults)
        if id == defaultProfileID { return }

        let activeID = activeProfileID(userDefaults: userDefaults)
        if id == activeID {
            setActiveProfileID(defaultProfileID, userDefaults: userDefaults)
        }

        var profiles = loadProfiles(userDefaults: userDefaults)
        profiles.removeAll(where: { $0.id == id })
        saveProfiles(profiles, userDefaults: userDefaults)
    }

    static func localStoreURL(
        applicationSupportDirectory: URL,
        userDefaults: UserDefaults = .standard
    ) -> URL {
        let profile = activeProfile(userDefaults: userDefaults)
        return applicationSupportDirectory.appendingPathComponent(profile.storeFilename)
    }

    static func deleteLocalStoreFileIfPresent(
        applicationSupportDirectory: URL,
        profileID: String,
        userDefaults: UserDefaults = .standard
    ) {
        let profiles = loadProfiles(userDefaults: userDefaults)
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }
        let url = applicationSupportDirectory.appendingPathComponent(profile.storeFilename)
        try? FileManager.default.removeItem(at: url)
    }
}

