//
//  SettingsService.swift
//  Oscar°
//
//  Created by Philipp Bolte on 23.02.22.
//
import CoreData
import SwiftUI
import Combine

/*
 * Settings storage should only have ONE object
 */
public class SettingService: ObservableObject {
    @Published var settings: Settings?
    private let context: NSManagedObjectContext
    private let pc = PersistenceController.shared

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
            /*
            for e in result {
                self.context.delete(e)
                try self.context.save()
            }
             */
            
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
                self.save()
            } else {
                self.settings = result.first!
            }
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
}
