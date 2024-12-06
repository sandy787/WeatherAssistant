import Foundation
import CoreLocation
import Combine

// Basic weather structures
struct WeatherResponse: Codable {
    let main: MainWeather
    let name: String
    let weather: [Weather]
    let timezone: Int
}

struct MainWeather: Codable {
    let temp: Double
}

struct Weather: Codable {
    let main: String
    let icon: String
}

// Our app's data models
struct WeatherData {
    let cityName: String
    let temperature: Int
    let condition: String
    let forecast: [DayForecast]
    let locationTime: LocationTime
}

struct DayForecast {
    let dayOfWeek: String
    let temperature: Int
    let condition: String
}

// Add GeocodingResponse structures
struct GeocodingResponse: Codable, Identifiable {
    let name: String
    let lat: Double
    let lon: Double
    let country: String
    let state: String?
    
    // Create a unique ID using UUID
    let id = UUID()
    
    // Add a computed property for display name
    var displayName: String {
        if let state = state {
            return "\(name), \(state), \(country)"
        }
        return "\(name), \(country)"
    }
}

// Add a new struct for time formatting
struct LocationTime {
    let timezone: Int
    weak var viewModel: WeatherViewModel?
    
    var localTime: String {
        let utcDate = Date()
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: timezone)
        formatter.dateFormat = "HH:mm"
        
        let formattedTime = formatter.string(from: utcDate)
        
        
        if let hour = Int(formattedTime.prefix(2)) {
            Task { @MainActor in
                viewModel?.isNight = (hour >= 19 || hour < 6)
            }
        }
        return formattedTime
    }
    
    var dayPeriod: String {
        // Create UTC date
        let utcDate = Date()
        
        // Create formatter with UTC timezone
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: timezone)
        formatter.dateFormat = "HH"
        
        if let hour = Int(formatter.string(from: utcDate)) {
            return (hour >= 6 && hour < 18) ? "day" : "night"
        }
        return "day"
    }
}

// Add this near the top with other response structs
struct ForecastResponse: Codable {
    let list: [ForecastItem]
}

struct ForecastItem: Codable {
    let dt_txt: String
    let main: MainWeather
    let weather: [Weather]
}

@MainActor
class WeatherViewModel: ObservableObject {
    @Published var weatherData: WeatherData?
    @Published var searchText: String = ""
    @Published var suggestions: [GeocodingResponse] = []
    @Published var isShowingSuggestions = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isNight: Bool = false
    
    var cancellables = Set<AnyCancellable>()
    
    private let apiKey = Config.weatherApiKey
    private var searchDebounceTimer: Timer?
    
    // Add location suggestions fetch
    func fetchLocationSuggestions() {
        searchDebounceTimer?.invalidate()
        
        // Validate input
        let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count >= 2 else {
            suggestions = []
            isShowingSuggestions = false
            return
        }
        
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.performLocationSearch()
        }
    }
    
    private func performLocationSearch() {
        guard let encodedCity = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.openweathermap.org/geo/1.0/direct?q=\(encodedCity)&limit=5&appid=\(apiKey)") else {
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let locations = try JSONDecoder().decode([GeocodingResponse].self, from: data)
                suggestions = locations
                isShowingSuggestions = !locations.isEmpty
            } catch {
                print("Error fetching suggestions: \(error)")
                suggestions = []
                isShowingSuggestions = false
            }
        }
    }
    
    func fetchWeather(for city: String) {
        isLoading = true
        errorMessage = nil
        
        guard let encodedCity = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.openweathermap.org/data/2.5/weather?q=\(encodedCity)&appid=\(apiKey)&units=metric") else {
            print("Invalid URL")
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let weather = try JSONDecoder().decode(WeatherResponse.self, from: data)
                
                // Fetch forecast data
                let forecast = try await fetchForecast(for: city)
                
                let condition = weather.weather.first?.icon ?? "01d"
                let sfSymbol = convertToSFSymbol(icon: condition)
                let locationTime = LocationTime(timezone: weather.timezone, viewModel: self)
                
                weatherData = WeatherData(
                    cityName: weather.name.uppercased(),
                    temperature: Int(round(weather.main.temp)),
                    condition: sfSymbol,
                    forecast: forecast,  // Use real forecast data instead of mock
                    locationTime: locationTime
                )
                
                // Print to console
                print("Weather for \(weather.name):")
                print("Temperature: \(Int(round(weather.main.temp)))°C")
                print("Condition: \(weather.weather.first?.main ?? "Unknown")")
                print("Local Time: \(locationTime.localTime)")
                
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to fetch weather: \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func createMockForecast() -> [DayForecast] {
        let days = ["MON", "TUE", "WED", "THU", "FRI"]
        return days.map { day in
            DayForecast(
                dayOfWeek: day,
                temperature: Int.random(in: 15...30),
                condition: "cloud.sun.fill"
            )
        }
    }
    
    private func convertToSFSymbol(icon: String) -> String {
        switch icon {
        case "01d": return "sun.max.fill"
        case "01n": return "moon.stars.fill"
        case "02d", "02n": return "cloud.sun.fill"
        case "03d", "03n": return "cloud.fill"
        case "04d", "04n": return "cloud.fill"
        case "09d", "09n": return "cloud.rain.fill"
        case "10d", "10n": return "cloud.heavyrain.fill"
        case "11d", "11n": return "cloud.bolt.rain.fill"
        case "13d", "13n": return "snow"
        case "50d", "50n": return "cloud.fog.fill"
        default: return "cloud.fill"
        }
    }
    
    private func fetchForecast(for city: String) async throws -> [DayForecast] {
        guard let encodedCity = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.openweathermap.org/data/2.5/forecast?q=\(encodedCity)&appid=\(apiKey)&units=metric") else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let forecastResponse = try JSONDecoder().decode(ForecastResponse.self, from: data)
        
        // Process forecast data
        return processForecastResponse(forecastResponse)
    }
    
    private func processForecastResponse(_ response: ForecastResponse) -> [DayForecast] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "EEE"
        
        var processedDays = Set<String>()
        var forecasts: [DayForecast] = []
        
        // Group forecasts by day
        var dailyForecasts: [String: [ForecastItem]] = [:]
        
        for item in response.list {
            guard let date = dateFormatter.date(from: item.dt_txt) else { continue }
            let dayString = displayFormatter.string(from: date).uppercased()
            
            if dailyForecasts[dayString] == nil {
                dailyForecasts[dayString] = []
            }
            dailyForecasts[dayString]?.append(item)
        }
        
        // Get noon forecast for each day (or closest to noon)
        for (day, items) in dailyForecasts {
            guard forecasts.count < 5 else { break }
            
            // Find forecast closest to noon (12:00)
            let noonForecast = items.min { item1, item2 in
                guard let date1 = dateFormatter.date(from: item1.dt_txt),
                      let date2 = dateFormatter.date(from: item2.dt_txt) else { return false }
                
                let calendar = Calendar.current
                let hour1 = calendar.component(.hour, from: date1)
                let hour2 = calendar.component(.hour, from: date2)
                
                return abs(hour1 - 12) < abs(hour2 - 12)
            }
            
            if let forecast = noonForecast {
                let condition = convertToSFSymbol(icon: forecast.weather.first?.icon ?? "01d")
                forecasts.append(DayForecast(
                    dayOfWeek: day,
                    temperature: Int(round(forecast.main.temp)),
                    condition: condition
                ))
            }
        }
        
        // Sort forecasts by day of week
        let calendar = Calendar.current
        let weekdaySymbols = calendar.shortWeekdaySymbols.map { $0.uppercased() }
        
        forecasts.sort { forecast1, forecast2 in
            guard let index1 = weekdaySymbols.firstIndex(of: forecast1.dayOfWeek),
                  let index2 = weekdaySymbols.firstIndex(of: forecast2.dayOfWeek) else {
                return false
            }
            return index1 < index2
        }
        
        return forecasts
    }
    
    func cleanup() {
        searchDebounceTimer?.invalidate()
        cancellables.removeAll()
    }
} 
