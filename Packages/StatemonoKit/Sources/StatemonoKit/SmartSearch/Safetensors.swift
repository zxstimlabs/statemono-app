import Foundation

/// A `.safetensors` file of 32-bit floats, read in place: the file is memory-mapped, so the weights stay on disk and the
/// system pages in only what's used, and can drop those pages again under memory pressure. The format is an 8-byte
/// little-endian header length, a JSON header naming each tensor's type, shape and byte range, then the data.
struct Safetensors: Sendable {
    struct Tensor: Sendable {
        let shape: [Int]
        /// Byte offset from the start of the file.
        let offset: Int
        var count: Int { shape.reduce(1, *) }
    }

    let data: Data
    let tensors: [String: Tensor]

    init(contentsOf url: URL) throws {
        data = try Data(contentsOf: url, options: .alwaysMapped)
        guard data.count >= 8 else { throw SearchModelError.damagedFile(url.lastPathComponent) }
        let headerLength = data.prefix(8).withUnsafeBytes { Int(UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self))) }
        guard headerLength > 0, 8 + headerLength <= data.count,
              let header = try JSONSerialization.jsonObject(with: data.subdata(in: 8..<(8 + headerLength))) as? [String: Any]
        else { throw SearchModelError.damagedFile(url.lastPathComponent) }

        var tensors: [String: Tensor] = [:]
        for (name, value) in header where name != "__metadata__" {
            // Only 32-bit floats are read; the file's other tensors (BERT's position ids) aren't needed.
            guard let entry = value as? [String: Any], entry["dtype"] as? String == "F32",
                  let shape = entry["shape"] as? [Int], let range = entry["data_offsets"] as? [Int], range.count == 2
            else { continue }
            let tensor = Tensor(shape: shape, offset: 8 + headerLength + range[0])
            guard range[1] - range[0] == tensor.count * 4, tensor.offset + tensor.count * 4 <= data.count, tensor.offset % 4 == 0 else {
                throw SearchModelError.damagedFile(url.lastPathComponent)
            }
            tensors[name] = tensor
        }
        self.tensors = tensors
    }

    func tensor(_ name: String, shape: [Int]) throws -> Tensor {
        guard let tensor = tensors[name], tensor.shape == shape else { throw SearchModelError.missingTensor(name) }
        return tensor
    }
}
