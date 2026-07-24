/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation

protocol NavigationServiceProviding: ObservableObject {
  var currentInstruction: NavigationInstruction? { get }
  var currentDestination: NavigationPOI? { get }
  var remainingDistance: Float { get }
  var currentWaypointIndex: Int { get }
  var totalWaypoints: Int { get }
  func getAvailablePOIs() -> [NavigationPOI]
}

extension AudioNavigationService: NavigationServiceProviding {}
extension DisplayNavRouteEngine: NavigationServiceProviding {}
