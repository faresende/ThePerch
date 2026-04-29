// FailableDecodable.swift
//
// Wraps any Decodable so that a single bad row in an array doesn't
// black-hole the whole decode. Pattern:
//
//   let wrapped = try decoder.decode([FailableDecodable<Insight>].self, from: data)
//   let good = wrapped.compactMap(\.value)
//
// Cheaper than the older `JSONSerialization → re-encode → JSONDecoder`
// pattern because we never round-trip through dictionary form — JSON
// is parsed once, the wrapper just absorbs per-element failures.

import Foundation

struct FailableDecodable<T: Decodable>: Decodable {
    let result: Result<T, Error>

    var value: T? {
        if case .success(let v) = result { return v }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            let v = try container.decode(T.self)
            self.result = .success(v)
        } catch {
            self.result = .failure(error)
        }
    }
}
