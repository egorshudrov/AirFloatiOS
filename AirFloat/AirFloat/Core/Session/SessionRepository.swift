import Foundation

enum SessionRepositoryError: Error, Equatable {
    case encodingFailed
    case decodingFailed
}

final class SessionRepository {
    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "airfloat.session.records.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func save(_ session: WorkoutSessionRecord) throws {
        var sessions = try loadSessions()
        sessions.removeAll { $0.id == session.id }
        sessions.append(session)
        sessions.sort { $0.timestampMs > $1.timestampMs }

        do {
            let data = try encoder.encode(sessions)
            defaults.set(data, forKey: storageKey)
        } catch {
            throw SessionRepositoryError.encodingFailed
        }
    }

    func latestSession() throws -> WorkoutSessionRecord? {
        try loadSessions().first
    }

    func loadSessions() throws -> [WorkoutSessionRecord] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }

        do {
            return try decoder.decode([WorkoutSessionRecord].self, from: data)
                .sorted { $0.timestampMs > $1.timestampMs }
        } catch {
            throw SessionRepositoryError.decodingFailed
        }
    }
}
