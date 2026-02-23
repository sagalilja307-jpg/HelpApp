//
//  LLMIntent.swift
//  Helper
//
//  Created by Saga Lilja on 2026-01-27.
//


import Foundation

enum LLMIntent: String, Codable {
    case none
    case calendar
    case reminder
    case note
    case ignore
    case sendMessage // 🆕 valfri, om du låter modellen föreslå detta
}
