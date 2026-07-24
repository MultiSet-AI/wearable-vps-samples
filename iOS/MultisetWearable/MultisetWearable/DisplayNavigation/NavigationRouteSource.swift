/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Combine

@MainActor
protocol NavigationRouteSource: AnyObject {
  var isNavigatingPublisher: AnyPublisher<Bool, Never> { get }
  var currentDestinationPublisher: AnyPublisher<NavigationPOI?, Never> { get }
  var currentWaypointIndexPublisher: AnyPublisher<Int, Never> { get }
  var currentNavigationPathPublisher: AnyPublisher<[Int]?, Never> { get }
}

extension AudioNavigationService: NavigationRouteSource {
  var isNavigatingPublisher: AnyPublisher<Bool, Never> { $isNavigating.eraseToAnyPublisher() }
  var currentDestinationPublisher: AnyPublisher<NavigationPOI?, Never> { $currentDestination.eraseToAnyPublisher() }
  var currentWaypointIndexPublisher: AnyPublisher<Int, Never> { $currentWaypointIndex.eraseToAnyPublisher() }
  var currentNavigationPathPublisher: AnyPublisher<[Int]?, Never> { $currentNavigationPath.eraseToAnyPublisher() }
}

extension DisplayNavRouteEngine: NavigationRouteSource {
  var isNavigatingPublisher: AnyPublisher<Bool, Never> { $isNavigating.eraseToAnyPublisher() }
  var currentDestinationPublisher: AnyPublisher<NavigationPOI?, Never> { $currentDestination.eraseToAnyPublisher() }
  var currentWaypointIndexPublisher: AnyPublisher<Int, Never> { $currentWaypointIndex.eraseToAnyPublisher() }
  var currentNavigationPathPublisher: AnyPublisher<[Int]?, Never> { $currentNavigationPath.eraseToAnyPublisher() }
}
