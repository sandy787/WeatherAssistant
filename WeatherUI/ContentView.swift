//
//  ContentView.swift
//  WeatherUI
//
//  Created by prajwal sanap on 29/10/24.
//

import SwiftUI
import Speech
import Combine
import AVFoundation

struct ContentView: View {
    @StateObject private var weatherViewModel = WeatherViewModel()
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @FocusState private var isSearchFocused: Bool
    @State private var isRecording = false
    
    var body: some View {
        ZStack {
            BackgroundView(isNight: weatherViewModel.isNight)
            
            ScrollView {
                VStack {
                    // Search Bar with Suggestions and Voice Button
                    VStack {
                        HStack {
                            TextField("Search city...", text: $weatherViewModel.searchText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .focused($isSearchFocused)
                                .onChange(of: weatherViewModel.searchText) { _ in
                                    weatherViewModel.fetchLocationSuggestions()
                                }
                                .accessibilityLabel("Search for a city")
                                .submitLabel(.search)
                                .onSubmit {
                                    if !weatherViewModel.searchText.isEmpty {
                                        weatherViewModel.fetchWeather(for: weatherViewModel.searchText)
                                        weatherViewModel.isShowingSuggestions = false
                                        isSearchFocused = false
                                    }
                                }
                            
                            // Voice Search Button
                            Button(action: {
                                if isRecording {
                                    speechRecognizer.stopRecording()
                                    isRecording = false
                                    // Fetch suggestions for the transcribed text if there's text
                                    if !weatherViewModel.searchText.isEmpty {
                                        weatherViewModel.fetchLocationSuggestions()
                                    }
                                } else {
                                    // Don't clear previous text when starting new recording
                                    speechRecognizer.startRecording()
                                    isRecording = true
                                }
                            }) {
                                Image(systemName: isRecording ? "mic.fill" : "mic")
                                    .foregroundColor(isRecording ? .red : .white)
                                    .padding(.horizontal, 8)
                            }
                            
                            // Search Button
                            Button(action: {
                                weatherViewModel.fetchWeather(for: weatherViewModel.searchText)
                                weatherViewModel.isShowingSuggestions = false
                                isSearchFocused = false
                            }) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top)
                        
                        // Suggestions List
                        if weatherViewModel.isShowingSuggestions {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(weatherViewModel.suggestions) { suggestion in
                                        Button(action: {
                                            weatherViewModel.searchText = suggestion.displayName
                                            weatherViewModel.fetchWeather(for: suggestion.name)
                                            weatherViewModel.isShowingSuggestions = false
                                            isSearchFocused = false
                                            // Stop recording if it's still active
                                            if isRecording {
                                                speechRecognizer.stopRecording()
                                                isRecording = false
                                            }
                                        }) {
                                            VStack(alignment: .leading) {
                                                Text(suggestion.name)
                                                    .foregroundColor(.primary)
                                                if let state = suggestion.state {
                                                    Text("\(state), \(suggestion.country)")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                } else {
                                                    Text(suggestion.country)
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            .padding(.vertical, 5)
                                            .padding(.horizontal)
                                        }
                                        Divider()
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .shadow(radius: 5)
                            .padding(.horizontal)
                        }
                    }
                    
                    // Rest of your weather content
                    if let weatherData = weatherViewModel.weatherData {
                        CityNameView(
                            cityName: weatherData.cityName,
                            localTime: weatherData.locationTime.localTime
                        )
                        
                        MainWeatherView(
                            imageName: weatherData.locationTime.dayPeriod == "night" ? "moon.stars.fill" : weatherData.condition,
                            temperature: weatherData.temperature
                        )
                        
                        HStack(spacing: 17.0) {
                            ForEach(weatherData.forecast, id: \.dayOfWeek) { forecast in
                                WeatherDayView(dayofWeek: forecast.dayOfWeek,
                                             imageName: forecast.condition,
                                             temperature: forecast.temperature)
                            }
                        }
                        .foregroundColor(.white)
                    } else if weatherViewModel.isLoading {
                        ProgressView()
                            .scaleEffect(2)
                            .tint(.white)
                    } else if let error = weatherViewModel.errorMessage {
                        Text(error)
                            .foregroundColor(.white)
                            .padding()
                    } else {
                        CityNameView(
                            cityName: "PUNE, IN",
                            localTime: "Loading..."
                        )
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        weatherViewModel.isNight.toggle()
                    }) {
                        WeatherButtonView(title: "Change Day Time",
                                        textColor: weatherViewModel.isNight ? .black : .blue,
                                        backgroundColor: .white)
                    }
                    .cornerRadius(15)
                    
                    Spacer()
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .onTapGesture {
            isSearchFocused = false
            weatherViewModel.isShowingSuggestions = false
        }
        .onAppear {
            weatherViewModel.fetchWeather(for: "Pune")
            // Update search text when speech recognition provides new text
            speechRecognizer.transcription
                .receive(on: DispatchQueue.main)
                .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
                .sink { [weak weatherViewModel] text in
                    guard let weatherViewModel = weatherViewModel else { return }
                    
                    // Only update if the text is different and not empty
                    if weatherViewModel.searchText != text && !text.isEmpty {
                        weatherViewModel.searchText = text
                        
                        // Stop recording after receiving transcription
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            speechRecognizer.stopRecording()
                            isRecording = false
                            // Fetch suggestions after stopping recording
                            weatherViewModel.fetchLocationSuggestions()
                        }
                    }
                }
                .store(in: &weatherViewModel.cancellables)
        }
    }
}

#Preview {
    ContentView()
}

struct WeatherDayView: View {
    var dayofWeek: String
    var imageName: String
    var temperature: Int
    var body: some View {
        
        VStack{
            Text(dayofWeek)
            Image(systemName: imageName)
                .symbolRenderingMode(.multicolor)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 50.0, height: 50.0)
                .accessibilityLabel("Weather condition: \(imageName)")
            Text(String(temperature)+"°C")
                .accessibilityLabel("Temperature \(temperature) degrees Celsius")
        }
    }
}

struct BackgroundView: View {
    var isNight: Bool
    var body: some View {
        LinearGradient(gradient: Gradient(colors: [isNight ? .black :.blue, isNight ? .gray : Color("lightBlue")]), startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

struct CityNameView: View {
    var cityName: String
    var localTime: String
    
    var body: some View {
        VStack(spacing: 5) {
            Text(cityName)
                .font(.system(size: 40))
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(localTime)
                .font(.system(size: 24))
                .foregroundColor(.white)
        }
        .padding(.top, 40)
    }
}

struct MainWeatherView : View {
    var imageName: String
    var temperature: Int
                
    var body: some View {
        VStack(spacing: 10.0){
            Image(systemName: imageName)
                .renderingMode(.original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 180.0, height: 180.0)
                .accessibilityLabel("Weather condition: \(imageName)")
            
            Text(String(temperature)+"°C")
                .font(.system(size: 80))
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .accessibilityLabel("Temperature \(temperature) degrees Celsius")
        }
        .padding(.bottom,30)
    }
}

