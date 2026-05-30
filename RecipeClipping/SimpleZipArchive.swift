import Foundation

enum SimpleZipArchive {
    enum ZipError: LocalizedError {
        case invalidArchive
        case unsupportedCompressionMethod
        case fileTooLarge

        var errorDescription: String? {
            switch self {
            case .invalidArchive:
                "バックアップZIPを読み取れませんでした。"
            case .unsupportedCompressionMethod:
                "対応していないZIP形式です。RecipeClipperで書き出したZIPを選んでください。"
            case .fileTooLarge:
                "バックアップに含まれるファイルが大きすぎます。"
            }
        }
    }

    static func archiveData(from directoryURL: URL) throws -> Data {
        let fileManager = FileManager.default
        let fileURLs = try fileManager
            .contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .flatMap { url -> [URL] in
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    return try fileManager.recursiveRegularFiles(in: url)
                }
                return [url]
            }
            .sorted { $0.path < $1.path }

        var output = Data()
        var centralDirectory = Data()
        var entries: [CentralDirectoryEntry] = []

        for fileURL in fileURLs {
            let relativePath = fileURL.path
                .replacingOccurrences(of: directoryURL.path + "/", with: "")
            let nameData = Data(relativePath.utf8)
            let fileData = try Data(contentsOf: fileURL)
            guard fileData.count <= Int(UInt32.max), output.count <= Int(UInt32.max) else {
                throw ZipError.fileTooLarge
            }

            let crc = CRC32.checksum(fileData)
            let localHeaderOffset = UInt32(output.count)
            output.appendUInt32(0x04034b50)
            output.appendUInt16(20)
            output.appendUInt16(0x0800)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt32(crc)
            output.appendUInt32(UInt32(fileData.count))
            output.appendUInt32(UInt32(fileData.count))
            output.appendUInt16(UInt16(nameData.count))
            output.appendUInt16(0)
            output.append(nameData)
            output.append(fileData)

            entries.append(CentralDirectoryEntry(
                nameData: nameData,
                crc: crc,
                size: UInt32(fileData.count),
                offset: localHeaderOffset
            ))
        }

        let centralDirectoryOffset = UInt32(output.count)
        for entry in entries {
            centralDirectory.appendUInt32(0x02014b50)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(20)
            centralDirectory.appendUInt16(0x0800)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(entry.crc)
            centralDirectory.appendUInt32(entry.size)
            centralDirectory.appendUInt32(entry.size)
            centralDirectory.appendUInt16(UInt16(entry.nameData.count))
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt16(0)
            centralDirectory.appendUInt32(0)
            centralDirectory.appendUInt32(entry.offset)
            centralDirectory.append(entry.nameData)
        }
        output.append(centralDirectory)

        output.appendUInt32(0x06054b50)
        output.appendUInt16(0)
        output.appendUInt16(0)
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt32(UInt32(centralDirectory.count))
        output.appendUInt32(centralDirectoryOffset)
        output.appendUInt16(0)
        return output
    }

    static func extract(_ data: Data, to destinationURL: URL) throws {
        var offset = 0

        while offset + 4 <= data.count {
            let signature = try data.uint32(at: offset)
            if signature == 0x02014b50 || signature == 0x06054b50 {
                break
            }
            guard signature == 0x04034b50 else {
                throw ZipError.invalidArchive
            }

            let flags = try data.uint16(at: offset + 6)
            let method = try data.uint16(at: offset + 8)
            guard method == 0 else { throw ZipError.unsupportedCompressionMethod }
            guard flags & 0x0008 == 0 else { throw ZipError.unsupportedCompressionMethod }

            let compressedSize = Int(try data.uint32(at: offset + 18))
            let fileNameLength = Int(try data.uint16(at: offset + 26))
            let extraLength = Int(try data.uint16(at: offset + 28))
            let nameStart = offset + 30
            let dataStart = nameStart + fileNameLength + extraLength
            let dataEnd = dataStart + compressedSize
            guard dataEnd <= data.count else { throw ZipError.invalidArchive }

            let nameData = data.subdata(in: nameStart..<(nameStart + fileNameLength))
            guard let fileName = String(data: nameData, encoding: .utf8),
                  !fileName.isEmpty,
                  !fileName.contains("..") else {
                throw ZipError.invalidArchive
            }

            let outputURL = destinationURL.appendingPathComponent(fileName)
            if fileName.hasSuffix("/") {
                try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.subdata(in: dataStart..<dataEnd).write(to: outputURL, options: [.atomic])
            }
            offset = dataEnd
        }
    }
}

private struct CentralDirectoryEntry {
    var nameData: Data
    var crc: UInt32
    var size: UInt32
    var offset: UInt32
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (0xedb88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
}

private extension FileManager {
    func recursiveRegularFiles(in directoryURL: URL) throws -> [URL] {
        guard let enumerator = enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    func uint16(at offset: Int) throws -> UInt16 {
        guard offset + 2 <= count else { throw SimpleZipArchive.ZipError.invalidArchive }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32(at offset: Int) throws -> UInt32 {
        guard offset + 4 <= count else { throw SimpleZipArchive.ZipError.invalidArchive }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
