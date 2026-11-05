import Foundation
import MapKit

/// MapKit has no CaseIterable category catalogue. Keep this explicit list aligned
/// with the SDK, guarding additions that are unavailable on older OS versions.
nonisolated enum ExcursionPOICategoryCatalog {
    struct Category: Identifiable, Sendable {
        let category: MKPointOfInterestCategory
        let name: String
        var id: String { category.rawValue }
    }

    struct Group: Identifiable, Sendable {
        let id: String
        let name: String
        let categoryIDs: Set<String>
    }

    static let categories: [Category] = {
        var result: [Category] = [
            .init(category: .animalService, name: String(localized: "Animal Service")),
            .init(category: .airport, name: String(localized: "Airport")),
            .init(category: .amusementPark, name: String(localized: "Amusement Park")),
            .init(category: .aquarium, name: String(localized: "Aquarium")),
            .init(category: .atm, name: String(localized: "ATMs")),
            .init(category: .automotiveRepair, name: String(localized: "Automotive Repair")),
            .init(category: .bakery, name: String(localized: "Bakery")),
            .init(category: .bank, name: String(localized: "Bank")),
            .init(category: .baseball, name: String(localized: "Baseball")),
            .init(category: .basketball, name: String(localized: "Basketball")),
            .init(category: .beach, name: String(localized: "Beach")),
            .init(category: .beauty, name: String(localized: "Beauty")),
            .init(category: .bowling, name: String(localized: "Bowling")),
            .init(category: .brewery, name: String(localized: "Brewery")),
            .init(category: .cafe, name: String(localized: "Cafés")),
            .init(category: .campground, name: String(localized: "Campground")),
            .init(category: .carRental, name: String(localized: "Car Rental")),
            .init(category: .castle, name: String(localized: "Castle")),
            .init(category: .conventionCenter, name: String(localized: "Convention Center")),
            .init(category: .distillery, name: String(localized: "Distillery")),
            .init(category: .evCharger, name: String(localized: "EV Charging")),
            .init(category: .fairground, name: String(localized: "Fairground")),
            .init(category: .fireStation, name: String(localized: "Fire Station")),
            .init(category: .fishing, name: String(localized: "Fishing")),
            .init(category: .fitnessCenter, name: String(localized: "Fitness Center")),
            .init(category: .foodMarket, name: String(localized: "Grocery Stores")),
            .init(category: .fortress, name: String(localized: "Fortress")),
            .init(category: .gasStation, name: String(localized: "Gas Station")),
            .init(category: .golf, name: String(localized: "Golf")),
            .init(category: .goKart, name: String(localized: "Go-Kart Tracks")),
            .init(category: .hiking, name: String(localized: "Hiking")),
            .init(category: .hospital, name: String(localized: "Hospital")),
            .init(category: .hotel, name: String(localized: "Hotel")),
            .init(category: .kayaking, name: String(localized: "Kayaking")),
            .init(category: .landmark, name: String(localized: "Landmark")),
            .init(category: .laundry, name: String(localized: "Laundry")),
            .init(category: .library, name: String(localized: "Library")),
            .init(category: .mailbox, name: String(localized: "Mailbox")),
            .init(category: .marina, name: String(localized: "Marina")),
            .init(category: .miniGolf, name: String(localized: "Mini Golf")),
            .init(category: .movieTheater, name: String(localized: "Movie Theater")),
            .init(category: .museum, name: String(localized: "Museum")),
            .init(category: .musicVenue, name: String(localized: "Music Venue")),
            .init(category: .nationalMonument, name: String(localized: "National Monument")),
            .init(category: .nationalPark, name: String(localized: "National Park")),
            .init(category: .nightlife, name: String(localized: "Nightlife")),
            .init(category: .park, name: String(localized: "Park")),
            .init(category: .parking, name: String(localized: "Parking")),
            .init(category: .pharmacy, name: String(localized: "Pharmacy")),
            .init(category: .planetarium, name: String(localized: "Planetarium")),
            .init(category: .police, name: String(localized: "Police")),
            .init(category: .postOffice, name: String(localized: "Post Office")),
            .init(category: .publicTransport, name: String(localized: "Public Transportation")),
            .init(category: .restaurant, name: String(localized: "Restaurant")),
            .init(category: .restroom, name: String(localized: "Restroom")),
            .init(category: .rockClimbing, name: String(localized: "Rock Climbing")),
            .init(category: .rvPark, name: String(localized: "RV Parks")),
            .init(category: .school, name: String(localized: "School")),
            .init(category: .skatePark, name: String(localized: "Skate Park")),
            .init(category: .skating, name: String(localized: "Skating")),
            .init(category: .skiing, name: String(localized: "Skiing")),
            .init(category: .soccer, name: String(localized: "Soccer")),
            .init(category: .spa, name: String(localized: "Spa")),
            .init(category: .stadium, name: String(localized: "Stadium")),
            .init(category: .store, name: String(localized: "Store")),
            .init(category: .surfing, name: String(localized: "Surfing")),
            .init(category: .swimming, name: String(localized: "Swimming")),
            .init(category: .tennis, name: String(localized: "Tennis")),
            .init(category: .theater, name: String(localized: "Theater")),
            .init(category: .university, name: String(localized: "University")),
            .init(category: .winery, name: String(localized: "Winery")),
            .init(category: .volleyball, name: String(localized: "Volleyball")),
            .init(category: .zoo, name: String(localized: "Zoo")),
        ]
        if #available(iOS 27.0, macCatalyst 27.0, macOS 27.0, *) {
            result += [
            .init(category: .airportTerminal, name: String(localized: "Airport Terminal")),
            .init(category: .automotiveDealership, name: String(localized: "Automotive Dealership")),
            .init(category: .commercialVehicleDealership, name: String(localized: "Commercial Vehicle Dealership")),
            .init(category: .informationBooth, name: String(localized: "Information Booth")),
            .init(category: .motorbikeDealership, name: String(localized: "Motorbike Dealership")),
            .init(category: .picnicArea, name: String(localized: "Picnic Area")),
            .init(category: .rangerStation, name: String(localized: "Ranger Station")),
            .init(category: .restArea, name: String(localized: "Rest Area")),
            .init(category: .scenicView, name: String(localized: "Scenic View")),
            .init(category: .ticketOffice, name: String(localized: "Ticket Office")),
            .init(category: .visitorCenter, name: String(localized: "Visitor Center")),
            ]
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    static let supportedIDs: Set<String> = Set(categories.map(\.id))

    static let groups: [Group] = [
        .init(id: "food-drink", name: String(localized: "Food & Drink"), categoryIDs: ids([
            .restaurant, .cafe, .bakery, .brewery, .winery, .distillery, .nightlife
        ])),
        .init(id: "shopping", name: String(localized: "Shopping"), categoryIDs: ids([.store, .pharmacy])),
        .init(id: "groceries", name: String(localized: "Groceries"), categoryIDs: ids([.foodMarket])),
        .init(id: "fuel-charging", name: String(localized: "Fuel & Charging"), categoryIDs: ids([.gasStation, .evCharger]))
    ]

    static var recommendedIDs: Set<String> {
        groups.reduce(into: Set<String>()) { $0.formUnion($1.categoryIDs) }
    }

    private static func ids(_ categories: [MKPointOfInterestCategory]) -> Set<String> {
        Set(categories.map(\.rawValue))
    }
}
