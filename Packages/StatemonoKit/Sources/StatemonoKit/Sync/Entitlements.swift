import Foundation
import MachO

/// The entitlements this app was signed with, read from its own executable. CloudKit doesn't return an error when the
/// app uses a container it isn't entitled to: `CKContainer(identifier:)` traps, and the app crashes at launch. That's
/// what TestFlight build 19 did on iPhone, archived unsigned so its App Store signature lost the iCloud entitlements.
/// Sync checks here first and stays off instead.
public enum Entitlements {
    /// The iCloud containers the app may use.
    public static let iCloudContainers: [String] = read(Bundle.main.executableURL)?.containers ?? []
    /// Whether the app may receive pushes, which `CKSyncEngine` needs.
    public static let hasPushEnvironment: Bool = read(Bundle.main.executableURL)?.push ?? false

    /// The parts sync needs from the entitlements of the executable at `url`, or nil if it has none.
    static func read(_ url: URL?) -> (containers: [String], push: Bool)? {
        guard let url, let data = try? Data(contentsOf: url, options: .alwaysMapped),
              let plist = entitlementsPlist(in: data),
              let entitlements = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        else { return nil }
        let containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String] ?? []
        let push = entitlements["aps-environment"] != nil || entitlements["com.apple.developer.aps-environment"] != nil
        return (containers, push)
    }

    /// The entitlements plist in a Mach-O file: from its code signature, or, in a simulator build, its
    /// `__TEXT,__entitlements` section, which wins there because the simulator's signature carries none. A universal
    /// binary is searched slice by slice.
    static func entitlementsPlist(in data: Data) -> Data? {
        guard data.count >= 8 else { return nil }
        let magic = data.uint32(at: 0, bigEndian: true)
        if magic == FAT_MAGIC || magic == FAT_MAGIC_64 {
            let count = Int(data.uint32(at: 4, bigEndian: true))
            let entrySize = magic == FAT_MAGIC_64 ? 32 : 20
            for index in 0..<count {
                let entry = 8 + index * entrySize
                let offset = magic == FAT_MAGIC_64
                    ? Int(data.uint64(at: entry + 8, bigEndian: true))
                    : Int(data.uint32(at: entry + 8, bigEndian: true))
                if let plist = entitlementsPlist(inSliceAt: offset, of: data) { return plist }
            }
            return nil
        }
        return entitlementsPlist(inSliceAt: 0, of: data)
    }

    private static func entitlementsPlist(inSliceAt base: Int, of data: Data) -> Data? {
        guard data.count >= base + MemoryLayout<mach_header_64>.size,
              data.uint32(at: base, bigEndian: false) == MH_MAGIC_64
        else { return nil }
        let commandCount = Int(data.uint32(at: base + 16, bigEndian: false))
        var command = base + MemoryLayout<mach_header_64>.size
        var signed: Data?
        var simulated: Data?
        for _ in 0..<commandCount {
            guard command + 8 <= data.count else { return nil }
            let type = data.uint32(at: command, bigEndian: false)
            let size = Int(data.uint32(at: command + 4, bigEndian: false))
            if type == UInt32(LC_CODE_SIGNATURE) {
                let offset = base + Int(data.uint32(at: command + 8, bigEndian: false))
                let length = Int(data.uint32(at: command + 12, bigEndian: false))
                signed = entitlementsBlob(in: data, at: offset, length: length)
            } else if type == UInt32(LC_SEGMENT_64), simulated == nil {
                simulated = entitlementsSection(in: data, segment: command, base: base)
            }
            guard size > 0 else { return nil }
            command += size
        }
        return simulated ?? signed
    }

    /// The code signature is a SuperBlob (big-endian): a magic number, its length, a count, then (type, offset) pairs.
    /// The entitlements blob has its own magic number, then its length, then the XML plist.
    private static func entitlementsBlob(in data: Data, at offset: Int, length: Int) -> Data? {
        let superBlobMagic: UInt32 = 0xFADE_0CC0
        let entitlementsMagic: UInt32 = 0xFADE_7171
        guard offset + 12 <= data.count, length >= 12, data.uint32(at: offset, bigEndian: true) == superBlobMagic else { return nil }
        let count = Int(data.uint32(at: offset + 8, bigEndian: true))
        for index in 0..<count {
            let entry = offset + 12 + index * 8
            guard entry + 8 <= data.count else { return nil }
            let blob = offset + Int(data.uint32(at: entry + 4, bigEndian: true))
            guard blob + 8 <= data.count, data.uint32(at: blob, bigEndian: true) == entitlementsMagic else { continue }
            let blobLength = Int(data.uint32(at: blob + 4, bigEndian: true))
            guard blobLength > 8, blob + blobLength <= data.count else { return nil }
            return data.subdata(in: (blob + 8)..<(blob + blobLength))
        }
        return nil
    }

    /// Simulator builds keep their entitlements in a `__TEXT,__entitlements` section rather than the signature.
    private static func entitlementsSection(in data: Data, segment: Int, base: Int) -> Data? {
        guard data.fixedString(at: segment + 8, length: 16) == "__TEXT" else { return nil }
        let sectionCount = Int(data.uint32(at: segment + 64, bigEndian: false))
        for index in 0..<sectionCount {
            let section = segment + 72 + index * 80
            guard section + 80 <= data.count, data.fixedString(at: section, length: 16) == "__entitlements" else { continue }
            let size = Int(data.uint64(at: section + 40, bigEndian: false))
            let offset = base + Int(data.uint32(at: section + 48, bigEndian: false))
            guard size > 0, offset + size <= data.count else { return nil }
            return data.subdata(in: offset..<(offset + size))
        }
        return nil
    }
}

private extension Data {
    func uint32(at offset: Int, bigEndian: Bool) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let value = self[(startIndex + offset)..<(startIndex + offset + 4)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return bigEndian ? value : value.byteSwapped
    }

    func uint64(at offset: Int, bigEndian: Bool) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        let value = self[(startIndex + offset)..<(startIndex + offset + 8)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return bigEndian ? value : value.byteSwapped
    }

    /// A NUL-padded name of up to `length` bytes, as Mach-O stores segment and section names.
    func fixedString(at offset: Int, length: Int) -> String {
        guard offset + length <= count else { return "" }
        let bytes = self[(startIndex + offset)..<(startIndex + offset + length)].prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }
}
