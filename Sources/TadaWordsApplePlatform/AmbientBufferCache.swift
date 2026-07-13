import TadaWordsDomain

struct AmbientScoreKey: Hashable, Sendable {
    let world: WorldTheme
    let isEmergency: Bool
}

/// Actor-owned, world-scoped PCM cache. Only the current world's normal and
/// rescue variants can be retained, so switching worlds never leaves another
/// world's score consuming memory.
struct AmbientBufferCache<Value> {
    private var cachedWorld: WorldTheme?
    private var entriesByEmergencyState: [Bool: Value] = [:]

    var count: Int { entriesByEmergencyState.count }

    func contains(_ key: AmbientScoreKey) -> Bool {
        cachedWorld == key.world && entriesByEmergencyState[key.isEmergency] != nil
    }

    mutating func select(world: WorldTheme) {
        guard cachedWorld != world else { return }
        cachedWorld = world
        entriesByEmergencyState.removeAll(keepingCapacity: true)
    }

    mutating func value(
        for key: AmbientScoreKey,
        create: () throws -> Value
    ) rethrows -> Value {
        if cachedWorld == key.world,
            let value = entriesByEmergencyState[key.isEmergency]
        {
            return value
        }

        // Render first. If synthesis ever fails, keep the last known-good
        // world intact rather than discarding its buffers prematurely.
        let createdValue = try create()
        select(world: key.world)
        entriesByEmergencyState[key.isEmergency] = createdValue
        return createdValue
    }
}
