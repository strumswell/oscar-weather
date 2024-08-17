import CoreData
import SwiftUI
import Combine

public class SettingService: ObservableObject {
    @Published var settings: Settings?
    private let context: NSManagedObjectContext
    private let pc = PersistenceController.shared
    private let nc = NotificationCenter.default

    init() {
        self.context = pc.container.viewContext
        self.update()
    }
    
    func save() {
        do {
            try self.context.save()
            update()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    private func update() {
        do {
            let fetchRequest: NSFetchRequest<Settings>
            fetchRequest = Settings.fetchRequest()
            let result = try self.context.fetch(fetchRequest)
            
            // Create default settings if empty
            if (result.count < 1) {
                let defaultSettings = Settings(context: self.context)
                defaultSettings.druckLayer = false
                defaultSettings.dwdLayer = true
                defaultSettings.rainviewerLayer = false
                defaultSettings.infrarotLayer = false
                defaultSettings.tempLayer = false
                defaultSettings.humidityLayer = false
                defaultSettings.windDirectionLayer = false
                defaultSettings.temperatureUnit = "celsius"
                defaultSettings.windSpeedUnit = "kmh"
                defaultSettings.precipitationUnit = "mm"
                self.save()
            } else {
                self.settings = result.first!
            }
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    func updateTemperatureUnit(_ unit: String) {
        settings?.temperatureUnit = unit
        save()
        nc.post(name: Notification.Name("UnitChanged"), object: nil)
    }
    
    func updateWindSpeedUnit(_ unit: String) {
        settings?.windSpeedUnit = unit
        save()
        nc.post(name: Notification.Name("UnitChanged"), object: nil)
    }
    
    func updatePrecipitationUnit(_ unit: String) {
        settings?.precipitationUnit = unit
        save()
        nc.post(name: Notification.Name("UnitChanged"), object: nil)
    }
}
