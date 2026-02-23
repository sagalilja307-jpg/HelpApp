//
//  BackendQuerying.swift
//  Helper
//
//  Created by Saga Lilja on 2026-02-19.
//


import Foundation

protocol BackendQuerying {
    func query(text: String) async throws -> BackendQueryResponseDTO
}
